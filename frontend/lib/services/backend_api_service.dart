import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/verification_response.dart';

class BackendApiService {
  // ==========================================================
  // DEVELOPMENT MODE
  // ==========================================================

  // true  = use fake response
  // false = use real Spring Boot backend
  static const bool mockMode = false;

  // ==========================================================
  // BACKEND URL
  // ==========================================================

  // Friend's laptop IPv4 address
  static const String baseUrl = 'https://cheddar-portion-dusk.ngrok-free.dev';

  // ==========================================================
  // VERIFY URL
  // ==========================================================

  Future<VerificationResponse> verifyUrl({
    required String url,
    String caption = '',
  }) async {
    // ========================================================
    // MOCK MODE
    // ========================================================

    if (mockMode) {
      await Future.delayed(
        const Duration(seconds: 3),
      );

      return VerificationResponse(
        verdict: 'FALSE',
        confidenceScore: 95.0,
        category: 'Government Schemes',
        explanationEn:
            'The claim could not be supported by reliable evidence. '
            'Official sources contradict the information presented '
            'in this content.',
        explanationTa:
            'இந்த தகவலில் கூறப்பட்டுள்ள கூற்றை நம்பகமான ஆதாரங்கள் '
            'ஆதரிக்கவில்லை. அதிகாரப்பூர்வ ஆதாரங்கள் இந்த தகவலுக்கு '
            'முரணாக உள்ளன.',
        proofLink: '',
      );
    }

    // ========================================================
    // VALIDATE URL
    // ========================================================

    final String cleanUrl = url.trim();

    if (cleanUrl.isEmpty) {
      throw Exception('Verification URL is empty.');
    }

    // ========================================================
    // BACKEND ENDPOINT
    // ========================================================

    final Uri uri = Uri.parse(
      '$baseUrl/api/v1/verify',
    );

    // ========================================================
    // JSON REQUEST BODY
    // ========================================================

    final Map<String, dynamic> requestBody = {
      'url': cleanUrl,
      'caption': caption.trim(),
    };

    final String jsonBody = jsonEncode(requestBody);

    // ========================================================
    // DEBUG INFORMATION
    // ========================================================

    debugPrint('========================================');
    debugPrint('INFOGUARD AI - BACKEND REQUEST');
    debugPrint('========================================');
    debugPrint('POST URL: $uri');
    debugPrint('Content-Type: application/json');
    debugPrint('Request Body: $jsonBody');
    debugPrint('========================================');

    try {
      // ======================================================
      // SEND JSON REQUEST
      // ======================================================

      final http.Response response = await http.post(
        uri,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonBody,
      );

      // ======================================================
      // DEBUG RESPONSE
      // ======================================================

      debugPrint('========================================');
      debugPrint('INFOGUARD AI - BACKEND RESPONSE');
      debugPrint('========================================');
      debugPrint('Status Code: ${response.statusCode}');
      debugPrint('Response Body: ${response.body}');
      debugPrint('========================================');

      // ======================================================
      // SUCCESS
      // ======================================================

      if (response.statusCode == 200) {
        if (response.body.trim().isEmpty) {
          throw Exception(
            'Backend returned 200 but the response body is empty.',
          );
        }

        final dynamic decoded = jsonDecode(response.body);

        if (decoded is! Map<String, dynamic>) {
          throw Exception(
            'Backend returned an unexpected JSON response.',
          );
        }

        return VerificationResponse.fromJson(decoded);
      }

      // ======================================================
      // 415 - UNSUPPORTED MEDIA TYPE
      // ======================================================

      if (response.statusCode == 415) {
        throw Exception(
          'Backend returned 415 Unsupported Media Type. '
          'Flutter sent application/json. '
          'Check that the Spring Boot server currently running '
          'on $baseUrl is the latest backend version and that '
          'the /api/v1/verify endpoint accepts application/json.',
        );
      }

      // ======================================================
      // OTHER BACKEND ERRORS
      // ======================================================

      throw Exception(
        'Backend returned status ${response.statusCode}: '
        '${response.body}',
      );
    } on http.ClientException catch (e) {
      debugPrint('HTTP CLIENT ERROR: $e');

      throw Exception(
        'Could not connect to the backend at $baseUrl. '
        'Make sure your friend\'s Spring Boot server is running '
        'and the laptop is reachable from this phone.',
      );
    } catch (e) {
      debugPrint('Verification error: $e');

      rethrow;
    }
  }
}