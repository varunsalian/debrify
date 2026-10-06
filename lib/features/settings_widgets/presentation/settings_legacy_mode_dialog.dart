// dart format off
import 'package:debrify/services/profiles/profile_bootstrap.dart' show ProfileBootstrap;
// dart format on
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// The "why is this install in legacy mode" dialog, opened from the Profiles
/// row on every settings layout.
///
/// This dialog IS the bug report. The one channel a television reporter
/// reliably has is a phone photo of the screen, so the captured reason —
/// including the error and its first stack frame on the unpredicted path —
/// is shown in full here rather than summarized. The reassurance lines are
/// as load-bearing as the diagnosis: legacy mode looks like data loss from
/// the couch, and it is precisely the opposite.
Future<void> showLegacyModeInfoDialog(BuildContext context) {
  final app = AppThemeScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: app.sheetSurface,
      title: const Text('Running in legacy mode'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ProfileBootstrap.legacyReasonSummary,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: app.core.tx,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your data is untouched — migration copies, never moves — and '
                'it retries automatically on every launch.\n\n'
                'If this keeps appearing, photograph this dialog and share it '
                'in the Discord: the text above identifies the cause.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: app.core.tx.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
