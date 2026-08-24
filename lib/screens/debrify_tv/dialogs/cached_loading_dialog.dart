import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import '../widgets/gradient_spinner.dart';
import 'spotlight_dialog.dart';

/// A loading dialog shown during channel cache operations.
///
/// Displays an animated spinner and shows a helpful hint after 15 seconds
/// for operations that take longer.
class CachedLoadingDialog extends StatefulWidget {
  final VoidCallback? onCancel;
  final String eyebrow;
  final String title;
  final String subtitle;

  const CachedLoadingDialog({
    super.key,
    this.onCancel,
    this.eyebrow = 'Tuning · finding a stream',
    this.title = 'Getting the next title ready',
    this.subtitle =
        'Checking the pool against your provider and playback rules.',
  });

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
    return PopScope(
      canPop: false,
      child: DebrifyTvSpotlightDialog(
        eyebrow: widget.eyebrow,
        title: widget.title,
        subtitle: widget.subtitle,
        icon: Icons.play_circle_outline_rounded,
        maxWidth: 620,
        actions: [
          if (widget.onCancel != null)
            DebrifyTvDialogButton(
              autofocus: true,
              label: 'Cancel',
              icon: Icons.close_rounded,
              onPressed: () {
                debugPrint('[CachedLoadingDialog] Cancel button pressed');
                widget.onCancel!();
              },
            ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const GradientSpinner(),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              height: 7,
              decoration: BoxDecoration(
                color: tv.fillWeak,
                borderRadius: BorderRadius.circular(99),
              ),
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: tv.accent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Text(
                _showHint
                    ? 'Rare keywords can take a little longer.'
                    : 'Searching the cached pool…',
                key: ValueKey(_showHint),
                style: TextStyle(
                  color: tv.textDim,
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
