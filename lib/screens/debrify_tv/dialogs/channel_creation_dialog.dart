import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import '../widgets/gradient_spinner.dart';
import 'spotlight_dialog.dart';

/// A dialog shown while creating/warming a new channel.
///
/// Displays the channel name, progress, and an optional countdown timer
/// showing estimated time remaining.
class ChannelCreationDialog extends StatefulWidget {
  final String channelName;
  final int? countdownSeconds;
  final void Function(BuildContext context) onReady;

  const ChannelCreationDialog({
    super.key,
    required this.channelName,
    this.countdownSeconds,
    required this.onReady,
  });

  @override
  State<ChannelCreationDialog> createState() => _ChannelCreationDialogState();
}

class _ChannelCreationDialogState extends State<ChannelCreationDialog> {
  Timer? _countdownTimer;
  int? _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;
    if (_remainingSeconds != null && _remainingSeconds! > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          final next = (_remainingSeconds ?? 0) - 1;
          if (next <= 0) {
            _remainingSeconds = 0;
            timer.cancel();
          } else {
            _remainingSeconds = next;
          }
        });
      });
    } else if (_remainingSeconds != null && _remainingSeconds! <= 0) {
      _remainingSeconds = 0;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tv = AppThemeScope.of(context).debrifyTv;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onReady(context);
    });
    return DebrifyTvSpotlightDialog(
      eyebrow: 'Tuning · building channel',
      title: widget.channelName,
      subtitle: 'Fetching titles, applying filters, and preparing the pool.',
      icon: Icons.auto_awesome_rounded,
      maxWidth: 620,
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
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: .62,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tv.accent, tv.accent.withValues(alpha: .55)],
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            widget.countdownSeconds == null
                ? 'Building the channel pool…'
                : _remainingSeconds != null && _remainingSeconds! > 0
                ? 'About ${_remainingSeconds!} seconds remaining…'
                : 'This one is taking a little longer than usual…',
            style: TextStyle(
              color: tv.textDim,
              fontFamily: 'JetBrainsMono',
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
