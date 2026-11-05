import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/verification_response.dart';

class ResultScreen extends StatelessWidget {
  final VerificationResponse result;
  final String verifiedUrl;

  const ResultScreen({
    super.key,
    required this.result,
    required this.verifiedUrl,
  });

  // ==========================================================
  // VERDICT COLOR
  // ==========================================================

  Color getVerdictColor() {
    switch (result.verdict.toUpperCase()) {
      case 'TRUE':
        return const Color(0xFF20A66A);

      case 'FALSE':
        return const Color(0xFFE5484D);

      case 'MISLEADING':
        return const Color(0xFFF59E0B);

      case 'SATIRE':
        return const Color(0xFF7657F6);

      default:
        return const Color(0xFF687386);
    }
  }

  // ==========================================================
  // VERDICT ICON
  // ==========================================================

  IconData getVerdictIcon() {
    switch (result.verdict.toUpperCase()) {
      case 'TRUE':
        return Icons.check_circle_rounded;

      case 'FALSE':
        return Icons.cancel_rounded;

      case 'MISLEADING':
        return Icons.warning_rounded;

      case 'SATIRE':
        return Icons.auto_awesome_rounded;

      default:
        return Icons.help_rounded;
    }
  }

  // ==========================================================
  // VERDICT DESCRIPTION
  // ==========================================================

  String _getVerdictDescription() {
    switch (result.verdict.toUpperCase()) {
      case 'TRUE':
        return 'This content appears to be true.';

      case 'FALSE':
        return 'This content appears to be false.';

      case 'MISLEADING':
        return 'This content contains misleading information.';

      case 'SATIRE':
        return 'This content appears to be satire.';

      default:
        return 'The content could not be clearly classified.';
    }
  }

  // ==========================================================
  // OPEN EVIDENCE SOURCE
  // ==========================================================

  Future<void> _openProofLink(BuildContext context) async {
    final String link = result.proofLink.trim();

    // --------------------------------------------------------
    // CHECK EMPTY LINK
    // --------------------------------------------------------

    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Evidence source is not available.',
          ),
        ),
      );
      return;
    }

    // --------------------------------------------------------
    // CREATE URI
    // --------------------------------------------------------

    final Uri? uri = Uri.tryParse(link);

    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' &&
            uri.scheme != 'https')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid evidence source link.',
          ),
        ),
      );
      return;
    }

    // --------------------------------------------------------
    // OPEN URL
    // --------------------------------------------------------

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      // ------------------------------------------------------
      // FAILED TO OPEN
      // ------------------------------------------------------

      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the evidence source.',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint(
        'Evidence source opening error: $e',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open the evidence source.',
            ),
          ),
        );
      }
    }
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final verdictColor = getVerdictColor();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),

      // ======================================================
      // APP BAR
      // ======================================================

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF14213D),
        title: const Text(
          'Verification Result',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),

      // ======================================================
      // BODY
      // ======================================================

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            10,
            20,
            30,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // ==================================================
              // RESULT HEADER
              // ==================================================

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFE5EAF2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: 0.035,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: verdictColor.withValues(
                          alpha: 0.10,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        getVerdictIcon(),
                        color: verdictColor,
                        size: 42,
                      ),
                    ),

                    const SizedBox(height: 16),

                    Text(
                      result.verdict,
                      style: TextStyle(
                        color: verdictColor,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _getVerdictDescription(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF687386),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),


              // ==================================================
              // VERIFIED URL
              // ==================================================

              buildCard(
                title: 'Verified Content',
                icon: Icons.link_rounded,
                child: Text(
                  verifiedUrl,
                  style: const TextStyle(
                    color: Color(0xFF687386),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),

              // ==================================================
              // EVIDENCE SOURCE
              // ==================================================

              if (result.proofLink.trim().isNotEmpty) ...[
                const SizedBox(height: 18),

                buildCard(
                  title: 'Evidence Source',
                  icon: Icons.verified_outlined,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Source used to support this verification:',
                        style: TextStyle(
                          color: Color(0xFF687386),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ----------------------------------------
                      // SOURCE URL
                      // ----------------------------------------

                      SelectableText(
                        result.proofLink,
                        style: const TextStyle(
                          color: Color(0xFF3867FF),
                          fontSize: 13,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ----------------------------------------
                      // VIEW SOURCE BUTTON
                      // ----------------------------------------

                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _openProofLink(context);
                          },
                          icon: const Icon(
                            Icons.open_in_new_rounded,
                            size: 18,
                          ),
                          label: const Text(
                            'View Source',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style:
                              OutlinedButton.styleFrom(
                            foregroundColor:
                                const Color(0xFF3867FF),
                            side: const BorderSide(
                              color: Color(0xFF3867FF),
                            ),
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // ==================================================
              // ENGLISH EXPLANATION
              // ==================================================

              buildCard(
                title: 'Explanation',
                icon: Icons.description_outlined,
                child: Text(
                  result.explanationEn,
                  style: const TextStyle(
                    color: Color(0xFF39465A),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ==================================================
              // TAMIL EXPLANATION
              // ==================================================

              buildCard(
                title: 'தமிழில் விளக்கம்',
                icon: Icons.translate_rounded,
                child: Text(
                  result.explanationTa,
                  style: const TextStyle(
                    color: Color(0xFF39465A),
                    fontSize: 14,
                    height: 1.7,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ==================================================
              // VERIFY ANOTHER
              // ==================================================

              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  icon: const Icon(
                    Icons.refresh_rounded,
                  ),
                  label: const Text(
                    'Verify Another URL',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF3867FF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // CARD BUILDER
  // ==========================================================

  Widget buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE5EAF2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.03,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: const Color(0xFF3867FF),
                size: 21,
              ),

              const SizedBox(width: 8),

              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF14213D),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          child,
        ],
      ),
    );
  }
}