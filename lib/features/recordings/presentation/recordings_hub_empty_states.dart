import 'package:debrify/features/recordings/presentation/recordings_hub_buttons.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Empty state ─────────────────────────────────────────────────────────────
class _EmptyDvr extends StatelessWidget {
  final VoidCallback onSchedule;
  final bool showAlarmBanner;
  final VoidCallback onOpenAlarmSettings;

  /// Shown first (the network share's status row).
  final Widget? top;
  const _EmptyDvr({
    this.top,
    required this.onSchedule,
    required this.showAlarmBanner,
    required this.onOpenAlarmSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
        ?top,
        if (showAlarmBanner) ...[
          _AlarmBanner(onTap: onOpenAlarmSettings),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 60),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: kRecordingsHubRec.withValues(alpha: 0.45),
                width: 2.5,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.fiber_manual_record_rounded,
                color: kRecordingsHubRec,
                size: 30,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Center(
          child: Text(
            'Your DVR is empty',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              'Record what\'s on now with the Record button on any live '
              'channel, set a recording from a programme guide, or schedule '
              'a channel and time yourself.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: RecordingsHubHubButton(
            icon: Icons.add_rounded,
            label: 'Schedule a recording',
            filled: true,
            autofocus: PlatformUtil.isTelevision,
            onPressed: onSchedule,
          ),
        ),
      ],
    );
  }
}

typedef RecordingsHubEmptyDvr = _EmptyDvr;

/// Evidence-based battery nudge: a recording died early and the app is not
/// excluded from optimization. Fix opens the system exemption dialog; the X
/// silences it until a NEWER interruption happens.
class _BatteryBanner extends StatelessWidget {
  final VoidCallback onFix;
  final VoidCallback onDismiss;
  const _BatteryBanner({required this.onFix, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: kRecordingsHubRec.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kRecordingsHubRec.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.battery_alert_rounded,
            color: Color(0xFFF59E0B),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onFix,
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'A recording stopped early',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'The phone likely put Debrify to sleep mid-capture. Tap '
                    'to exclude Debrify from battery optimization so long '
                    'recordings run to the end.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: Colors.white.withValues(alpha: 0.45),
            ),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

typedef RecordingsHubBatteryBanner = _BatteryBanner;

class _AlarmBanner extends StatefulWidget {
  final VoidCallback onTap;
  const _AlarmBanner({required this.onTap});

  @override
  State<_AlarmBanner> createState() => _AlarmBannerState();
}

typedef RecordingsHubAlarmBanner = _AlarmBanner;

class _AlarmBannerState extends State<_AlarmBanner> {
  /// Live, never cached: Flutter does not guarantee the falling edge of
  /// `onFocusChange` — popping a route opened with OK restores focus to the
  /// modal scope rather than to a row, so rows that were focus-walked on the
  /// way in are never told they lost it and keep painting as focused. See the
  /// note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode => _ownFocusNode ??= FocusNode();
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? kRecordingsHubGold
                  : const Color(0xFFF59E0B).withValues(alpha: 0.35),
              width: _focused ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Exact alarms are off',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scheduled recordings can\'t start until "Alarms & '
                      'reminders" is allowed. Tap to open system settings.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
