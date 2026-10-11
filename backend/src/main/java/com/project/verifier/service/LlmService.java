package com.project.verifier.service;

import java.io.File;
import java.nio.file.Files;
import java.util.Base64;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class LlmService {

    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    @Value("${app.groq.api-key}")
    private String groqApiKey;

    public LlmService(RestClient.Builder restClientBuilder, ObjectMapper objectMapper) {
        this.restClient = restClientBuilder.build();
        this.objectMapper = objectMapper;
    }

    public String translateAudioToEnglish(File audioFile) {
        try {
            MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
            body.add("file", new FileSystemResource(audioFile));
            body.add("model", "whisper-large-v3");
            body.add("response_format", "text");

            return restClient.post()
                    .uri("https://api.groq.com/openai/v1/audio/translations")
                    .header("Authorization", "Bearer " + groqApiKey)
                    .contentType(MediaType.MULTIPART_FORM_DATA)
                    .body(body)
                    .retrieve()
                    .body(String.class);
        } catch (Exception e) {
            throw new RuntimeException("Failed to translate audio: " + e.getMessage(), e);
        }
    }

    public String extractVisualContext(List<File> frames) {
        if (frames == null || frames.isEmpty()) {
            return "No visual context detected.";
        }

        try {
            // Encode the primary extracted frame (first frame)
            File firstFrame = frames.get(0);
            byte[] imageBytes = Files.readAllBytes(firstFrame.toPath());
            String base64Image = Base64.getEncoder().encodeToString(imageBytes);

            Map<String, Object> payload = Map.of(
                    "model", "llama-3.2-11b-vision-preview",
                    "messages", List.of(
                            Map.of("role", "user", "content", List.of(
                                    Map.of("type", "text", "text", "Extract on-screen text banners and describe the visual scene concisely in 2 sentences in English."),
                                    Map.of("type", "image_url", "image_url", Map.of("url", "data:image/jpeg;base64," + base64Image))
                            ))
                    ),
                    "max_tokens", 250,
                    "temperature", 0.2
            );

            String response = restClient.post()
                    .uri("https://api.groq.com/openai/v1/chat/completions")
                    .header("Authorization", "Bearer " + groqApiKey)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(payload)
                    .retrieve()
                    .body(String.class);

            JsonNode root = objectMapper.readTree(response);
            return root.path("choices").get(0).path("message").path("content").asText("");
        } catch (Exception e) {
            // If the key lacks vision model access or the frame is empty, gracefully degrade to caption/audio
            return "Visual context unavailable.";
        }
    }
}