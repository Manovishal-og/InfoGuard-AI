package com.project.verifier.entity;

import java.time.LocalDateTime;
import java.util.UUID;

import org.hibernate.annotations.CreationTimestamp;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Data;

@Entity
@Table(name = "verification_records")
@Data
public class VerificationRecord {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;
    
    private String mediaUrl;
    
    @Column(columnDefinition = "TEXT")
    private String audioTranscript;
    
    @Column(columnDefinition = "TEXT")
    private String visualContext;
    
    private String category;
    
    @Column(columnDefinition = "TEXT")
    private String searchEvidence;
    
    private String verdict;
    
    @Column(columnDefinition = "TEXT")
    private String explanationEn;
    
    @Column(columnDefinition = "TEXT")
    private String explanationTa;
    
    private Long latencyMs;
    
    @CreationTimestamp
    private LocalDateTime createdAt;

    // Add this near your other fields
    @Column(columnDefinition = "TEXT")
    private String proofLink;


    public String getProofLink() { return proofLink; }
    public void setProofLink(String proofLink) { this.proofLink = proofLink; }
}
