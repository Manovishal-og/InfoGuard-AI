package com.project.verifier.service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class TavilySearchService {

    @Value("${app.tavily.api-key}")
    private String tavilyApiKey;

    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    // Disallowed domains: video platforms, social feeds, and search engines
    private static final List<String> EXCLUDED_DOMAINS = List.of(
            "youtube.com", "youtu.be", "instagram.com", "facebook.com",
            "tiktok.com", "twitter.com", "x.com", "google.com",
            "reddit.com", "threads.net", "pinterest.com", "vimeo.com"
    );

    public TavilySearchService(RestClient.Builder restClientBuilder, ObjectMapper objectMapper) {
        this.restClient = restClientBuilder.build();
        this.objectMapper = objectMapper;
    }

    public record SearchEvidence(String contentSummary, String topUrl, List<String> backupUrls) {}

    public SearchEvidence searchEvidence(String query) {
        try {
            String cleanQuery = query.replaceAll("#[A-Za-z0-9_]+", "")
                                     .replaceAll("(?i)instagram|reel|shorts?|youtube|share|viral|subscribe|follow", "")
                                     .trim();
            if (cleanQuery.length() > 200) {
                cleanQuery = cleanQuery.substring(0, 200);
            }

            Map<String, Object> body = new HashMap<>();
            body.put("api_key", tavilyApiKey);
            body.put("query", cleanQuery + " news fact check");
            body.put("max_results", 6);
            body.put("search_depth", "advanced");
            body.put("exclude_domains", List.of(
                "instagram.com", "facebook.com", "tiktok.com", "twitter.com", "x.com", "google.com", "youtube.com", "youtu.be"
            ));

            String response = restClient.post()
                    .uri("https://api.tavily.com/search")
                    .header("Content-Type", "application/json")
                    .body(body)
                    .retrieve()
                    .body(String.class);

            JsonNode root = objectMapper.readTree(response);
            JsonNode results = root.path("results");

            if (results.isArray() && !results.isEmpty()) {
                StringBuilder summary = new StringBuilder();
                String verifiedUrl = "";
                List<String> backupUrls = new ArrayList<>();

                for (JsonNode item : results) {
                    String url = item.path("url").asText("");
                    
                    // Add YouTube exclusions to the backup URL filter
                    if (!url.contains("instagram.com") && !url.contains("facebook.com") && 
                        !url.contains("youtube.com") && !url.contains("youtu.be")) {
                        backupUrls.add(url); // Save all valid article links
                        if (verifiedUrl.isEmpty()) {
                            verifiedUrl = url;
                        }
                    }
                    summary.append("- Source: ").append(item.path("title").asText()).append("\n");
                    summary.append("  Details: ").append(item.path("content").asText()).append("\n\n");
                }

                return new SearchEvidence(summary.toString(), verifiedUrl, backupUrls);
            }

            return new SearchEvidence("No clinical or verified web records found.", "", new ArrayList<>());
        } catch (Exception e) {
            return new SearchEvidence("Search failed or timed out: " + e.getMessage(), "", new ArrayList<>());
        }
    }

    private boolean isTrustworthyUrl(String url) {
        if (url == null || url.isBlank()) return false;
        String lowerUrl = url.toLowerCase();
        return EXCLUDED_DOMAINS.stream().noneMatch(lowerUrl::contains);
    }
}