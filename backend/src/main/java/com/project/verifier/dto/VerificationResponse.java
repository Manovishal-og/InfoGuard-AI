package com.project.verifier.dto;

public class VerificationResponse {
    private String verdict;
    private String explanationEn;
    private String explanationTa;
    private String category;
    private String proofLink;

    public String getVerdict() { return verdict; }
    public void setVerdict(String verdict) { this.verdict = verdict; }
    public String getExplanationEn() { return explanationEn; }
    public void setExplanationEn(String explanationEn) { this.explanationEn = explanationEn; }
    public String getExplanationTa() { return explanationTa; }
    public void setExplanationTa(String explanationTa) { this.explanationTa = explanationTa; }
    public String getCategory() { return category; }
    public void setCategory(String category) { this.category = category; }
    public String getProofLink() { return proofLink; }
    public void setProofLink(String proofLink) { this.proofLink = proofLink; }
}