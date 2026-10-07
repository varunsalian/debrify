import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef PremiumizeFeedbackDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
});

class PremiumizeFeedback {
  PremiumizeFeedback(this._deps);
  final PremiumizeFeedbackDeps _deps;

  // ── Misc helpers ─────────────────────────────────────────────────────────────

  void showLoadingDialog(String message) {
    if (!_deps.mounted()) return;
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (_) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  void dismissDialog() {
    if (_deps.mounted() &&
        Navigator.of(_deps.context(), rootNavigator: true).canPop()) {
      Navigator.of(_deps.context(), rootNavigator: true).pop();
    }
  }

  void showSnackBar(String message, {bool isError = true, Duration? duration}) {
    if (!_deps.mounted()) return;
    final app = AppThemeScope.of(_deps.context());
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF22C55E),
                borderRadius: app.shape.br(8),
              ),
              child: Icon(
                isError ? Icons.error : Icons.check_circle,
                color: Colors.white,
                size: 16,
              ),
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
        duration: duration ?? const Duration(seconds: 3),
      ),
    );
  }
}
