import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'gform_iframe.dart';

class EmbeddedFeedbackModal extends StatelessWidget {
  final String gformEmbedUrl;

  const EmbeddedFeedbackModal({
    super.key,
    this.gformEmbedUrl = 'https://docs.google.com/forms/d/e/1FAIpQLSccVou0M1k5iHBcA3U1FrsYya14GFVNX7ZRD2Q9fC2ykEJAGA/viewform?embedded=true',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final subTextColor = textColor.withValues(alpha: 0.65);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08);

    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double dialogWidth = (screenWidth * 0.92).clamp(320.0, 740.0);
    final double dialogHeight = (screenHeight * 0.88).clamp(400.0, 850.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
              blurRadius: 28,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.rate_review_rounded,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Feedback & Suggestions',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          'Fill out the form directly below',
                          style: TextStyle(
                            fontSize: 12,
                            color: subTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: subTextColor, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: borderColor),

            // Embedded Form Container
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                child: kIsWeb
                    ? buildGFormIframe(gformEmbedUrl)
                    : Container(
                        color: theme.scaffoldBackgroundColor,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.assignment_rounded,
                              size: 48,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'GEC Compass Feedback Form',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Submit suggestions, missing places, or bug reports directly to our team.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13.5, color: subTextColor),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final uri = Uri.parse(gformEmbedUrl);
                                try {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                } catch (_) {}
                              },
                              icon: const Icon(Icons.open_in_browser),
                              label: const Text('Open Feedback Form'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
