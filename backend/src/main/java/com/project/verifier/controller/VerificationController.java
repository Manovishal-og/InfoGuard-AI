package com.project.verifier.controller;

import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.project.verifier.dto.VerificationRequest;
import com.project.verifier.dto.VerificationResponse;
import com.project.verifier.service.VerificationService;

@RestController
@RequestMapping("/api/v1/verify")
@CrossOrigin(origins = "*")
public class VerificationController {

    private final VerificationService verificationService;

    public VerificationController(VerificationService verificationService) {
        this.verificationService = verificationService;
    }

    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<VerificationResponse> verifyContent(@RequestBody VerificationRequest request) {
        if (request == null || request.getUrl() == null || request.getUrl().isBlank()) {
            throw new IllegalArgumentException("The 'url' field is required in the JSON body.");
        }

        String caption = request.getCaption() != null ? request.getCaption() : "";
        VerificationResponse response = verificationService.processMediaVerification(request.getUrl(), caption);
        return ResponseEntity.ok(response);
    }
}