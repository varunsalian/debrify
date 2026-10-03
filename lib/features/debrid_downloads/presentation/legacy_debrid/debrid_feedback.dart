import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef DebridFeedbackDeps = ({BuildContext Function() context});

class DebridFeedback {
  DebridFeedback(this._deps);
  final DebridFeedbackDeps _deps;

  void copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showSuccess('Download link(s) copied to clipboard!');
  }

  void showSuccess(String message) {
    // Messenger lookup first: it is the pre-existing liveness check on this
    // context, so an unmounted caller fails exactly where it always did.
    final messenger = ScaffoldMessenger.of(_deps.context());
    final app = AppThemeScope.of(_deps.context());
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: app.shape.br(8),
              ),
              // Ink PINNED with its surface. The fill above is a `const Color`
              // that does not follow the palette, so page ink on it is exactly
              // the both-directions mistake — near-black on a semantic green
              // under a paper theme, or Phosphor's amber on amber.
              child: Icon(Icons.check, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: app.cloud.dialogSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void showError(String message) {
    // Messenger lookup first: it is the pre-existing liveness check on this
    // context, so an unmounted caller fails exactly where it always did.
    final messenger = ScaffoldMessenger.of(_deps.context());
    final app = AppThemeScope.of(_deps.context());
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: app.shape.br(8),
              ),
              // Ink PINNED with its surface. The fill above is a `const Color`
              // that does not follow the palette, so page ink on it is exactly
              // the both-directions mistake — near-black on a semantic green
              // under a paper theme, or Phosphor's amber on amber.
              child: Icon(Icons.error, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: app.cloud.dialogSurface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: app.shape.br(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
