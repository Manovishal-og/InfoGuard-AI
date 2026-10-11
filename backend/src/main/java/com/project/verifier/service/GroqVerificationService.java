package com.project.verifier.service;

import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

@Service
public class GroqVerificationService {

    @Value("${app.groq.api-key}")
    private String groqApiKey;

    @Value("${app.groq.model:qwen/qwen3.8-27b}")
    private String groqModel;

    private final RestClient restClient;
    private final ObjectMapper objectMapper;

    public GroqVerificationService(RestClient.Builder restClientBuilder, ObjectMapper objectMapper) {
        this.restClient = restClientBuilder.build();
        this.objectMapper = objectMapper;
    }

    public String generateFactCheck(String caption, String transcript, String searchEvidence, String proofUrl)
            throws Exception {
        // Prevent empty URL hallucinations by enforcing a trusted baseline
        String safeProofUrl = (proofUrl == null || proofUrl.isBlank())
                ? "https://www.who.int/news-room/fact-in-pictures"
                : proofUrl;

        String prompt = """
                You are an elite, objective fact-checking AI.
                Evaluate the following social media post claim using both the provided Web Evidence and your verified medical/scientific nutritional knowledge base.
                [CLAIM INPUTS]
                Caption: %s
                Spoken Audio: %s
                [RETRIEVED WEB EVIDENCE]
                %s
                [RULES]
                1. For scientific, nutritional, or biological facts, evaluate nutritional reality accurately. If the statement is medically or scientifically accurate, mark it 'TRUE'.
                2. Never mark a factual biological/nutritional claim 'FALSE' merely because the retrieved search snippet was brief.
                3. For the 'proofLink', you MUST output EXACTLY this verified URL: "%s". Do not hallucinate, invent, add Markdown, or search for a different link.

                Return ONLY a valid JSON object matching this schema:
                {
                  "verdict": "TRUE" | "FALSE" | "MISLEADING",
                  "category": "Health/Nutrition/Politics/General",
                  "explanationEn": "Clear explanation of the claim and factual confirmation in English.",
                  "explanationTa": "Accurate, clear Tamil translation of the explanation.",
                  "proofLink": "The exact URL provided in rule 3"
                }
                """
                .formatted(caption, transcript, searchEvidence, safeProofUrl);

        Map<String, Object> payload = Map.of(
                "model", groqModel,
                "messages", List.of(
                        Map.of("role", "system", "content",
                                "You are an accurate, bilingual fact-checking AI. Respond only in valid JSON."),
                        Map.of("role", "user", "content", prompt)),
                "response_format", Map.of("type", "json_object"),
                "temperature", 0.1);

        String response = restClient.post()
                .uri("https://api.groq.com/openai/v1/chat/completions")
                .header("Authorization", "Bearer " + groqApiKey)
                .header("Content-Type", "application/json")
                .body(payload)
                .retrieve()
                .body(String.class);

        JsonNode rootNode = objectMapper.readTree(response);
        return rootNode.path("choices").get(0).path("message").path("content").asText();
    }
}