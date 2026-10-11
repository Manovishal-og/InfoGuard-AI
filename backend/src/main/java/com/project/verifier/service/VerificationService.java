package com.project.verifier.service;

import java.io.File;
import java.util.List;      // Imports the List interface
import java.util.Optional;
import java.util.concurrent.CompletableFuture;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.project.verifier.dto.VerificationResponse;
import com.project.verifier.entity.VerificationRecord;
import com.project.verifier.repository.VerificationRepository;

@Service
public class VerificationService {

    private static final Logger log = LoggerFactory.getLogger(VerificationService.class);

    private final VerificationRepository verificationRepository;
    private final MediaExtractionService extractionService;
    private final LlmService llmService;
    private final TavilySearchService tavilySearchService;
    private final GroqVerificationService groqVerificationService;
    private final ObjectMapper objectMapper;
    private static final List<String> UNTRUSTED_DOMAINS = List.of(
            "youtube.com", "youtu.be", "instagram.com", "facebook.com",
            "tiktok.com", "twitter.com", "x.com", "google.com",
            "reddit.com", "threads.net", "pinterest.com", "vimeo.com");

    public VerificationService(VerificationRepository verificationRepository,
            MediaExtractionService extractionService,
            LlmService llmService,
            TavilySearchService tavilySearchService,
            GroqVerificationService groqVerificationService,
            ObjectMapper objectMapper) {
        this.verificationRepository = verificationRepository;
        this.extractionService = extractionService;
        this.llmService = llmService;
        this.tavilySearchService = tavilySearchService;
        this.groqVerificationService = groqVerificationService;
        this.objectMapper = objectMapper;
    }

    private boolean isInvalidProofLink(String url) {
        if (url == null || url.isBlank())
            return true;
        String lower = url.toLowerCase();
        return UNTRUSTED_DOMAINS.stream().anyMatch(lower::contains);
    }

    public VerificationResponse processMediaVerification(String instagramUrl, String providedCaption) {
        long pipelineStartTime = System.currentTimeMillis();
        long stepStart;

        log.info("--- Starting Verification Pipeline for URL: {} ---", instagramUrl);

        // 1. Sanitize URL for cache lookup and safe downloading
        String cleanUrl = (instagramUrl != null && instagramUrl.contains("?"))
                ? instagramUrl.split("\\?")[0].trim()
                : (instagramUrl != null ? instagramUrl.trim() : "");

        // 2. Check Database Cache
        stepStart = System.currentTimeMillis();
        Optional<VerificationRecord> existingRecord = verificationRepository.findByMediaUrl(cleanUrl);
        if (existingRecord.isPresent()) {
            log.info("[✓] Cache Hit: Returned saved result in {} ms", (System.currentTimeMillis() - stepStart));
            VerificationRecord record = existingRecord.get();
            VerificationResponse response = new VerificationResponse();
            response.setVerdict(record.getVerdict());
            response.setExplanationEn(record.getExplanationEn());
            response.setExplanationTa(record.getExplanationTa());
            response.setCategory(record.getCategory());
            response.setProofLink(record.getProofLink());
            return response;
        }
        log.info("[!] Cache Miss: Proceeding with full extraction in {} ms", (System.currentTimeMillis() - stepStart));

        MediaExtractionService.ExtractionResult media = null;
        try {
            // 3. Extract Media
            stepStart = System.currentTimeMillis();
            media = extractionService.extractMedia(cleanUrl);
            final var extractedMedia = media;
            log.info("[✓] Media Extraction (Video/Audio/Frames) completed in {} ms",
                    (System.currentTimeMillis() - stepStart));

            String finalCaption = (providedCaption == null || providedCaption.isBlank())
                    ? extractedMedia.caption()
                    : providedCaption;

            // 4. Run Audio Transcription & Visual Analysis Concurrently
            stepStart = System.currentTimeMillis();

            CompletableFuture<String> audioTask = CompletableFuture.supplyAsync(() -> {
                // GUARDRAIL: Safely handle photo posts or muted reels (0-byte audio) to prevent
                // exceptions
                if (extractedMedia.audio() != null && extractedMedia.audio().exists()
                        && extractedMedia.audio().length() > 0) {
                    try {
                        return llmService.translateAudioToEnglish(extractedMedia.audio());
                    } catch (Exception e) {
                        log.warn("Audio translation failed, degrading gracefully: {}", e.getMessage());
                        return "Audio unavailable.";
                    }
                }
                return "No audio available or muted post.";
            });

            CompletableFuture<String> visualTask = CompletableFuture.supplyAsync(() -> {
                if (extractedMedia.frames() != null && !extractedMedia.frames().isEmpty()) {
                    try {
                        return llmService.extractVisualContext(extractedMedia.frames());
                    } catch (Exception e) {
                        log.warn("Visual extraction failed, degrading gracefully: {}", e.getMessage());
                        return "Visual context unavailable.";
                    }
                }
                return "No visual context detected.";
            });

            CompletableFuture.allOf(audioTask, visualTask).join();
            String transcript = audioTask.get();
            String visualContext = visualTask.get();
            log.info("[✓] Parallel AI Feature Extraction (Audio STT & Vision) completed in {} ms",
                    (System.currentTimeMillis() - stepStart));

            // 5. Build Dynamic Search Query & Execute RAG
            stepStart = System.currentTimeMillis();
            String searchSeed = !finalCaption.isBlank() ? finalCaption
                    : (transcript.startsWith("No audio") ? visualContext : transcript);
            String searchQuery = searchSeed.length() > 120 ? searchSeed.substring(0, 120) : searchSeed;

            var searchResult = tavilySearchService.searchEvidence(searchQuery);
            log.info("[✓] Live Web Evidence Retrieval (RAG) completed in {} ms",
                    (System.currentTimeMillis() - stepStart));

            // 6. Ground and Verify Claim with Final LLM
            stepStart = System.currentTimeMillis();
            String combinedEvidenceContext = String.format("Visual Details: %s | Web Evidence: %s",
                    visualContext, searchResult.contentSummary());

            String jsonFactCheck = groqVerificationService.generateFactCheck(
                    finalCaption, transcript, combinedEvidenceContext, searchResult.topUrl());

            // Clean Markdown markers if returned
            String cleanedJson = jsonFactCheck.trim();
            if (cleanedJson.startsWith("```json")) {
                cleanedJson = cleanedJson.substring(7);
            } else if (cleanedJson.startsWith("```")) {
                cleanedJson = cleanedJson.substring(3);
            }
            if (cleanedJson.endsWith("```")) {
                cleanedJson = cleanedJson.substring(0, cleanedJson.length() - 3);
            }

            VerificationResponse response = objectMapper.readValue(cleanedJson.trim(), VerificationResponse.class);

            // 6b. Link Validation: Pass the LLM's chosen link AND the Tavily backup links
            String targetUrl = (response.getProofLink() != null && !response.getProofLink().isBlank())
                    ? response.getProofLink()
                    : searchResult.topUrl();

            String validatedLink = validateProofLink(targetUrl, searchResult.backupUrls());
            response.setProofLink(validatedLink);

            log.info("[✓] Final LLM Fact-Checking & Link Validation completed in {} ms",
                    (System.currentTimeMillis() - stepStart));

            // 7. Persist Result to PostgreSQL
            long totalLatency = System.currentTimeMillis() - pipelineStartTime;
            VerificationRecord newRecord = new VerificationRecord();
            newRecord.setMediaUrl(cleanUrl);
            newRecord.setAudioTranscript(transcript);
            newRecord.setVisualContext(visualContext);
            newRecord.setCategory(response.getCategory());
            newRecord.setVerdict(response.getVerdict());
            newRecord.setExplanationEn(response.getExplanationEn());
            newRecord.setExplanationTa(response.getExplanationTa());
            newRecord.setProofLink(response.getProofLink());
            newRecord.setLatencyMs(totalLatency);
            verificationRepository.save(newRecord);

            log.info("--- Pipeline Finished Successfully in {} ms ---", totalLatency);
            return response;

        } catch (Exception e) {
            log.error("[X] CRITICAL PIPELINE FAILURE for URL {}: {}", cleanUrl, e.getMessage(), e);
            throw new RuntimeException("Verification pipeline failed: " + e.getMessage(), e);
        } finally {
            // 8. Disk Cleanup: Always execute to prevent server storage bloat
            if (media != null) {
                try {
                    if (media.video() != null && media.video().exists())
                        media.video().delete();
                    if (media.audio() != null && media.audio().exists())
                        media.audio().delete();
                    if (media.frames() != null) {
                        media.frames().forEach(File::delete);
                    }
                    log.info("[✓] Temporary media files successfully purged from disk.");
                } catch (Exception cleanupEx) {
                    log.error("[!] Failed to clean up some temporary files: {}", cleanupEx.getMessage());
                }
            }
        }
    }

    private String validateProofLink(String primaryUrl, java.util.List<String> backupUrls) {
        java.util.List<String> urlsToTest = new java.util.ArrayList<>();

        // 1. Clean Markdown artifacts if the LLM hallucinated them
        String cleanPrimary = primaryUrl;
        if (cleanPrimary != null && cleanPrimary.contains("](")) {
            cleanPrimary = cleanPrimary.substring(cleanPrimary.indexOf("](") + 2).replace(")", "");
        }

        // 2. Prioritize the LLM's chosen URL, but STRICTLY block Google, Social Media,
        // and YouTube
        if (cleanPrimary != null && !cleanPrimary.isBlank()
                && !cleanPrimary.contains("instagram.com")
                && !cleanPrimary.contains("google.com")
                && !cleanPrimary.contains("youtube.com")
                && !cleanPrimary.contains("youtu.be")) {
            urlsToTest.add(cleanPrimary);
        }

        // 3. Append all backup articles found by Tavily, excluding Google and YouTube
        if (backupUrls != null) {
            for (String backup : backupUrls) {
                if (!backup.contains("google.com") && !backup.contains("youtube.com") && !backup.contains("youtu.be")) {
                    urlsToTest.add(backup);
                }
            }
        }

        // Fast 2-second timeout configuration to test for live articles
        org.springframework.http.client.SimpleClientHttpRequestFactory factory = new org.springframework.http.client.SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(java.time.Duration.ofSeconds(2));
        factory.setReadTimeout(java.time.Duration.ofSeconds(2));
        org.springframework.web.client.RestClient pingClient = org.springframework.web.client.RestClient.builder()
                .requestFactory(factory).build();

        // 4. Test candidate article links in order to ensure they are active (not 404)
        for (String url : urlsToTest) {
            try {
                var status = pingClient.get()
                        .uri(url)
                        .header("User-Agent",
                                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
                        .header("Accept", "text/html,application/xhtml+xml")
                        .retrieve()
                        .toBodilessEntity()
                        .getStatusCode();

                if (status.is2xxSuccessful() || status.is3xxRedirection()) {
                    log.info("Validated active article link: {}", url);
                    return url;
                }
            } catch (Exception e) {
                log.warn("[!] Article link {} failed ping test ({}). Checking next...", url, e.getMessage());
            }
        }

        // 5. If ping checks are blocked by anti-bot firewalls (Cloudflare), use the
        // first non-social article candidate
        if (!urlsToTest.isEmpty()) {
            return urlsToTest.get(0);
        }

        // 6. Trusted fallback to an established fact-checking/authoritative source
        return "https://www.reuters.com/fact-check/";
    }

    private String generateGoogleFallback(String query) {
        try {
            // Cap the query length to prevent massive URLs, and URL-encode it safely
            String safeQuery = query.length() > 60 ? query.substring(0, 60) : query;
            String encodedQuery = java.net.URLEncoder.encode("fact check " + safeQuery, "UTF-8");
            return "[https://www.google.com/search?q=](https://www.google.com/search?q=)" + encodedQuery;
        } catch (Exception e) {
            return "[https://www.google.com/](https://www.google.com/)";
        }
    }
}