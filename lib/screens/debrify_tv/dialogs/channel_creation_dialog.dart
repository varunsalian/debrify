import 'dart:async';
import 'package:flutter/material.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onReady(context);
    });
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF1B1B1F), Color(0xFF101014)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.4),
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
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const SizedBox(
              width: 240,
              child: Text(
                'Fetching torrents and getting everything ready. Hang tight!',
                style: TextStyle(
                  color: Colors.white70,
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
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
