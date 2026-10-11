package com.project.verifier.dto;

public class VerificationRequest {
    private String url;
    private String caption;

    public VerificationRequest() {}

    public VerificationRequest(String url, String caption) {
        this.url = url;
        this.caption = caption;
    }

    public String getUrl() {
        return url;
    }

    public void setUrl(String url) {
        this.url = url;
    }

    public String getCaption() {
        return caption;
    }

    public void setCaption(String caption) {
        this.caption = caption;
    }
}