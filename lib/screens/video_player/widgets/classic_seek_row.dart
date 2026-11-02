import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../services/player_controls_display_settings.dart';
import '../services/playback_ui_clock.dart';
import 'seek_bubble.dart';

/// The classic dock's seek row: elapsed time, the red bar with its time
/// bubble, and the duration readout that taps between total and time left.
class ClassicSeekRow extends StatelessWidget {
  const ClassicSeekRow({
    super.key,
    required this.clock,
    required this.onSeekBarChangedStart,
    required this.onSeekBarChanged,
    required this.onSeekBarChangeEnd,
  });

  final ValueListenable<PlaybackUiClockValue> clock;
  final VoidCallback onSeekBarChangedStart;
  final ValueChanged<double> onSeekBarChanged;
  final VoidCallback onSeekBarChangeEnd;

  static const _red = Color(0xFFE50914);
  static const _readout = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PlaybackUiClockValue>(
      valueListenable: clock,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds <= 0
            ? const Duration(seconds: 1)
            : value.duration;
        final progress = (value.position.inMilliseconds / total.inMilliseconds)
            .clamp(0.0, 1.0);
        return Row(
          children: [
            Text(format(value.position), style: _readout),
            const SizedBox(width: 12),
            Expanded(
              child: SeekBubble(
                duration: value.duration,
                progress: progress,
                inset: 12,
                format: format,
                fill: Colors.black.withValues(alpha: 0.78),
                ink: Colors.white,
                fontSize: 12,
                child: _slider(context, progress),
              ),
            ),
            // Tap: the total or the time left. The target matches the
            // slider's height (this row must not grow on a short screen) and
            // takes in the gap beside it.
            ValueListenableBuilder<bool>(
              valueListenable: PlayerControlsDisplaySettings.showRemaining,
              builder: (context, remaining, _) => Semantics(
                container: true,
                button: true,
                onTapHint: remaining ? 'Show total time' : 'Show time left',
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: PlayerControlsDisplaySettings.toggleRemaining,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 24),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsetsDirectional.only(start: 12),
                        child: Text(
                          remaining ? timeLeft(value) : format(value.duration),
                          style: _readout,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _slider(BuildContext context, double progress) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: _red,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 6,
          elevation: 2,
        ),
        thumbColor: _red,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      ),
      child: Slider(
        min: 0,
        max: 1,
        value: progress,
        onChangeStart: (_) => onSeekBarChangedStart(),
        onChanged: onSeekBarChanged,
        onChangeEnd: (_) => onSeekBarChangeEnd(),
      ),
    );
  }

  /// `-42:55`: what is left, never below zero. No "-00:00" before the
  /// duration is known.
  static String timeLeft(PlaybackUiClockValue value) {
    if (value.duration <= Duration.zero) return format(value.duration);
    final left = value.duration - value.position;
    return '-${format(left.isNegative ? Duration.zero : left)}';
  }

  /// `07:05`, or `01:08:00` past the hour; a leading `-` for a negative.
  static String format(Duration d) {
    final sign = d.isNegative ? '-' : '';
    final abs = d.abs();
    final h = abs.inHours;
    final m = abs.inMinutes % 60;
    final s = abs.inSeconds % 60;
    if (h > 0) {
      return '$sign${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$sign${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
