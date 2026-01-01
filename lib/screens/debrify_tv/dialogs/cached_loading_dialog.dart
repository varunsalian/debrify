import 'dart:async';
import 'package:flutter/material.dart';
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
              gradient: const LinearGradient(
                colors: [Color(0xFF1B1B1F), Color(0xFF101014)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border:
                  Border.all(color: Colors.white.withOpacity(0.1), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
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
                      ? const Text(
                          'Rare keywords can take a little longer.',
                          key: ValueKey('hint'),
                          style: TextStyle(
                            color: Colors.white70,
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
                        backgroundColor: Colors.white.withOpacity(0.1),
                        foregroundColor: Colors.white70,
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
