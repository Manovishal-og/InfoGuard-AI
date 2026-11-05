class VerificationResponse {
  final String verdict;
  final double confidenceScore;
  final String category;
  final String explanationEn;
  final String explanationTa;
  final String proofLink;

  VerificationResponse({
    required this.verdict,
    required this.confidenceScore,
    required this.category,
    required this.explanationEn,
    required this.explanationTa,
    required this.proofLink,
  });

  factory VerificationResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return VerificationResponse(
      verdict: json['verdict']?.toString() ?? 'UNKNOWN',
      confidenceScore:
          (json['confidenceScore'] as num?)?.toDouble() ?? 0.0,
      category: json['category']?.toString() ?? 'Unknown',
      explanationEn:
          json['explanationEn']?.toString() ?? '',
      explanationTa:
          json['explanationTa']?.toString() ?? '',
      proofLink:
          json['proofLink']?.toString() ?? '',
    );
  }
}