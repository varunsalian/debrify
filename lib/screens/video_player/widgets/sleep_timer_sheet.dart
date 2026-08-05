import 'package:flutter/material.dart';

import '../constants/color_constants.dart';

/// What a sleep timer is set to.
enum SleepTimerMode {
  off,

  /// Stop once [SleepTimerSelection.minutes] have elapsed.
  countdown,

  /// Stop when the current item finishes instead of advancing to the next.
  endOfItem,
}

/// A picked sleep-timer setting. [minutes] is only meaningful for
/// [SleepTimerMode.countdown].
class SleepTimerSelection {
  final SleepTimerMode mode;
  final int minutes;

  const SleepTimerSelection(this.mode, [this.minutes = 0]);

  static const off = SleepTimerSelection(SleepTimerMode.off);
}

/// Modal bottom sheet for arming the sleep timer.
///
/// Mirrors the "Sleep timer" row in the native TV players' unified menu, so
/// the two surfaces offer the same choices in the same order.
class SleepTimerSheet {
  static const List<int> minuteOptions = <int>[15, 30, 45, 60, 90];

  /// Shows the picker and returns the chosen setting, or null if dismissed.
  ///
  /// [armedMinutes] is the preset originally picked — the checkmark follows it
  /// rather than [minutesLeft], which stops matching any option the moment the
  /// countdown ticks. [minutesLeft] is shown alongside it as the live
  /// remaining time. [allowEndOfItem] is false for live content, which has no
  /// end to stop at.
  static Future<SleepTimerSelection?> show(
    BuildContext context, {
    required SleepTimerMode current,
    int armedMinutes = 0,
    int minutesLeft = 0,
    bool allowEndOfItem = true,
  }) {
    return showModalBottomSheet<SleepTimerSelection>(
      context: context,
      backgroundColor: VideoPlayerColors.darkBackground,
      // The player runs landscape, where an unconstrained sheet is capped near
      // half the (already short) height — eight rows would clip "End of
      // episode" straight off the bottom. Scroll-controlled plus a scrollable
      // body keeps every choice reachable on a phone in landscape.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Text(
                  'Sleep timer',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: Text(
                  'Playback pauses and the screen is released so the device '
                  'can sleep. Your position is saved.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ),
              _tile(
                context,
                label: 'Off',
                selected: current == SleepTimerMode.off,
                value: SleepTimerSelection.off,
              ),
              for (final minutes in minuteOptions)
                _tile(
                  context,
                  label: '$minutes minutes',
                  selected: current == SleepTimerMode.countdown &&
                      armedMinutes == minutes,
                  trailingText: current == SleepTimerMode.countdown &&
                          armedMinutes == minutes
                      ? '$minutesLeft min left'
                      : null,
                  value: SleepTimerSelection(
                    SleepTimerMode.countdown,
                    minutes,
                  ),
                ),
              if (allowEndOfItem)
                _tile(
                  context,
                  label: 'End of episode',
                  selected: current == SleepTimerMode.endOfItem,
                  value: const SleepTimerSelection(SleepTimerMode.endOfItem),
                ),
              const SizedBox(height: 8),
            ],
            ),
          ),
        );
      },
    );
  }

  static Widget _tile(
    BuildContext context, {
    required String label,
    required bool selected,
    required SleepTimerSelection value,
    String? trailingText,
  }) {
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF6366F1) : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: selected
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (trailingText != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      trailingText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ),
                const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
              ],
            )
          : null,
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}
