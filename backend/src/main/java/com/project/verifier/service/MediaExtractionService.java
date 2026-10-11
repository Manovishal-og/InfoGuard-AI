package com.project.verifier.service;

import java.io.File;
import java.io.InputStream;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class MediaExtractionService {

    private static final Logger log = LoggerFactory.getLogger(MediaExtractionService.class);

    @Value("${app.media.temp-dir:/tmp/verifier_media}")
    private String baseTempDir;

    @Value("${app.apify.token}")
    private String apifyToken;

    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    public MediaExtractionService(RestClient.Builder restClientBuilder, ObjectMapper objectMapper) {
        this.restClient = restClientBuilder.build();
        this.objectMapper = objectMapper;
    }

    public record ExtractionResult(File video, File audio, List<File> frames, String caption) {}

    public ExtractionResult extractMedia(String rawInstagramUrl) throws Exception {
        String baseName = UUID.randomUUID().toString();
        Path dirPath = Paths.get(baseTempDir);
        if (!Files.exists(dirPath)) {
            Files.createDirectories(dirPath);
        }

        // 1. Sanitize URL to prevent truncation from tracking parameters
        String cleanUrl = rawInstagramUrl.split("\\?")[0].trim();

        File downloadedFile = null;
        String caption = "";

        // 2. Fast-Path: Attempt Native yt-dlp first (3-6s Execution)
        try {
            ProcessBuilder pb = new ProcessBuilder(
                    "yt-dlp",
                    "-f", "b[ext=mp4]/b",
                    "--write-description",
                    "--no-playlist",
                    "-o", dirPath.resolve(baseName + ".%(ext)s").toString(),
                    cleanUrl
            );
            pb.redirectErrorStream(true);
            Process proc = pb.start();
            
            // Timeout limits the process to 12 seconds so blocked requests fail fast
            boolean finished = proc.waitFor(50, TimeUnit.SECONDS);

            if (finished && proc.exitValue() == 0) {
                File[] matched = dirPath.toFile().listFiles((d, name) -> name.startsWith(baseName) && !name.contains("_frame_"));
                if (matched != null) {
                    for (File f : matched) {
                        if (f.getName().endsWith(".description")) {
                            caption = Files.readString(f.toPath()).trim();
                        } else if (!f.getName().endsWith(".wav")) {
                            downloadedFile = f;
                        }
                    }
                }
            } else if (!finished) {
                proc.destroyForcibly();
            }
        } catch (Exception e) {
            log.warn("Direct download encountered an exception: {}", e.getMessage());
        }

        // 3. Fallback: Managed Cloud Scraper (Apify) if yt-dlp hits bot shields or encounters carousels
        if (downloadedFile == null || !downloadedFile.exists()) {
            log.info("yt-dlp blocked or incompatible URL. Falling back to Apify for: {}", cleanUrl);
            
            Map<String, Object> runInput = Map.of(
                    "directUrls", List.of(cleanUrl),
                    "resultsType", "details",
                    "resultsLimit", 1
            );

            // Use the lightweight api-scraper to bypass headless browser overhead
            String apifyEndpoint = "https://api.apify.com/v2/acts/apify~instagram-api-scraper/run-sync-get-dataset-items?token="
                    + apifyToken + "&timeout=500";

            String responseJson = restClient.post()
                    .uri(apifyEndpoint)
                    .header("Content-Type", "application/json")
                    .body(runInput)
                    .retrieve()
                    .body(String.class);

            JsonNode itemsArray = objectMapper.readTree(responseJson);
            if (!itemsArray.isArray() || itemsArray.isEmpty()) {
                throw new RuntimeException("Scraper failed to extract post details or post is private.");
            }

            JsonNode post = itemsArray.get(0);
            
            // Guarantee caption extraction for the LLM context
            caption = post.path("caption").asText(""); 
            String videoUrl = post.path("videoUrl").asText(null);

            if (videoUrl != null && !videoUrl.isBlank()) {
                Path videoPath = dirPath.resolve(baseName + ".mp4");
                try (InputStream in = new URI(videoUrl).toURL().openStream()) {
                    Files.copy(in, videoPath, StandardCopyOption.REPLACE_EXISTING);
                }
                downloadedFile = videoPath.toFile();
            } else {
                // Carousel or Photo Post handling
                JsonNode imagesNode = post.path("images");
                List<String> imageUrls = new ArrayList<>();
                if (imagesNode.isArray() && !imagesNode.isEmpty()) {
                    imagesNode.forEach(img -> imageUrls.add(img.asText()));
                } else if (post.hasNonNull("displayUrl")) {
                    imageUrls.add(post.path("displayUrl").asText());
                }

                if (!imageUrls.isEmpty()) {
                    Path imgPath = dirPath.resolve(baseName + ".jpg");
                    try (InputStream in = new URI(imageUrls.get(0)).toURL().openStream()) {
                        Files.copy(in, imgPath, StandardCopyOption.REPLACE_EXISTING);
                    }
                    downloadedFile = imgPath.toFile();
                }
            }
        }

        if (downloadedFile == null || !downloadedFile.exists()) {
            throw new RuntimeException("Unable to acquire media stream for URL: " + cleanUrl);
        }

        List<File> frames = new ArrayList<>();
        File audioFile = null;
        String fileName = downloadedFile.getName().toLowerCase();

        // 4. Modality Split & Feature Extraction
        if (fileName.matches(".*\\.(jpg|jpeg|png|webp)$")) {
            // Static Image or Carousel: Pass visual directly, skip audio demuxing
            frames.add(downloadedFile);
        } else {
            // Video Reel: Demux 3 Keyframes and 16kHz Audio concurrently
            Path audioPath = dirPath.resolve(baseName + ".wav");

            // Extract lightweight frames (480px, q:v 7) for instantaneous LLM upload
            ProcessBuilder framesPb = new ProcessBuilder(
                    "ffmpeg", "-y", "-i", downloadedFile.getAbsolutePath(),
                    "-vf", "fps=1/10,scale=480:-1",
                    "-frames:v", "3",
                    "-q:v", "7",
                    dirPath.resolve(baseName + "_frame_%d.jpg").toString()
            );

            ProcessBuilder audioPb = new ProcessBuilder(
                    "ffmpeg", "-y", "-i", downloadedFile.getAbsolutePath(),
                    "-vn", "-ar", "16000", "-ac", "1",
                    audioPath.toString()
            );

            Process procFrames = framesPb.start();
            Process procAudio = audioPb.start();

            procFrames.waitFor();
            procAudio.waitFor();

            File[] extracted = dirPath.toFile().listFiles((d, name) -> name.startsWith(baseName + "_frame_"));
            if (extracted != null) {
                frames.addAll(List.of(extracted));
            }

            // Guardrail against 0-byte ghost audio files from muted videos
            if (audioPath.toFile().exists() && audioPath.toFile().length() > 0) {
                audioFile = audioPath.toFile();
            }
        }

        return new ExtractionResult(downloadedFile, audioFile, frames, caption);
    }
}