import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import '../widgets/gradient_spinner.dart';

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
    // Wrap in GestureDetector to absorb all taps and prevent click-through
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // Absorb all taps
      child: Center(
        child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            // 0xFF101014 is the gradient's deep stop and no role holds it —
            // nearest are `controlBg` 0xFF141414 and `dialogBg` 0xFF0F0F0F,
            // both different colours. So the card is HALF themed: top stop
            // follows the theme, bottom stop is pinned dark. The title and
            // body ink below stay theme ink for that reason — on a paper
            // theme no single ink reads over both halves, and scoring against
            // one stop would only relocate the unreadable half. Fixing this
            // properly needs a deep-stop role in DebrifyTvTokens.
            colors: [tv.noticeBg, tv.dialogDeep],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: tv.fillWeak, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const GradientSpinner(),
            const SizedBox(height: 18),
            Text(
              'Building "${widget.channelName}"',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: 240,
              child: Text(
                'Fetching torrents and getting everything ready. Hang tight!',
                style: TextStyle(
                  color: tv.textDim,
                  fontSize: 13,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (widget.countdownSeconds != null) ...[
              const SizedBox(height: 12),
              Text(
                _remainingSeconds != null && _remainingSeconds! > 0
                    ? 'About ${_remainingSeconds!}s remaining…'
                    : 'Taking longer than usual…',
                style: TextStyle(color: tv.textDim, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
