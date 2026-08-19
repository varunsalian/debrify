import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import '../widgets/gradient_spinner.dart';

/// A loading dialog shown during channel cache operations.
///
/// Displays an animated spinner and shows a helpful hint after 15 seconds
/// for operations that take longer.
class CachedLoadingDialog extends StatefulWidget {
  final VoidCallback? onCancel;

  const CachedLoadingDialog({super.key, this.onCancel});

  @override
  State<CachedLoadingDialog> createState() => _CachedLoadingDialogState();
}

class _CachedLoadingDialogState extends State<CachedLoadingDialog> {
  Timer? _hintTimer;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) {
        setState(() {
          _showHint = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = AppThemeScope.of(context).debrifyTv;
    // Wrap in PopScope to block back button dismissal
    return PopScope(
      canPop: false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // Absorb all taps
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                // 0xFF101014 is the gradient's deep stop and no role holds it
                // — left literal rather than mapped to a near-miss. (Nearest
                // are `controlBg` 0xFF141414 and `dialogBg` 0xFF0F0F0F, both
                // different colours.) The card is therefore HALF themed: the
                // top stop follows the theme, the bottom is pinned dark. The
                // ink below is deliberately NOT scored against a stop — on a
                // paper theme no single ink reads over both halves, so
                // scoring would only move the unreadable half rather than fix
                // it. This needs a deep-stop role in DebrifyTvTokens first.
                colors: [tv.noticeBg, tv.dialogDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: tv.fillWeak, width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const GradientSpinner(),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: _showHint
                      ? Text(
                          'Rare keywords can take a little longer.',
                          key: const ValueKey('hint'),
                          style: TextStyle(
                            color: tv.textDim,
                            fontSize: 13,
                            height: 1.35,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : const SizedBox(height: 0, key: ValueKey('no_hint')),
                ),
                const SizedBox(height: 18),
                if (widget.onCancel != null)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      autofocus: true,
                      onPressed: () {
                        debugPrint('[CachedLoadingDialog] Cancel button pressed');
                        widget.onCancel!();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: tv.fillWeak,
                        foregroundColor: tv.textDim,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
