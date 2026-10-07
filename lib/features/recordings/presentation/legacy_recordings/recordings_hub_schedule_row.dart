import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Scheduled row ───────────────────────────────────────────────────────────
class _ScheduleRow extends StatefulWidget {
  final ScheduledRecording schedule;
  final ValueNotifier<DateTime> now;
  final String timeText;
  final String Function(Duration) fmtCountdown;
  final bool autofocus;
  final VoidCallback onCancel;

  const _ScheduleRow({
    required this.schedule,
    required this.now,
    required this.timeText,
    required this.fmtCountdown,
    required this.autofocus,
    required this.onCancel,
  });

  @override
  State<_ScheduleRow> createState() => _ScheduleRowState();
}

typedef RecordingsHubScheduleRow = _ScheduleRow;

class _ScheduleRowState extends State<_ScheduleRow> {
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
    final s = widget.schedule;
    final title = s.programmeTitle.isEmpty ? s.channelName : s.programmeTitle;
    return Focus(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onFocusChange: (_) => setState(() {}),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onCancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onCancel,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: _focused
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _focused
                  ? kRecordingsHubGold
                  : Colors.white.withValues(alpha: 0.06),
              width: _focused ? 1.8 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: kRecordingsHubRec.withValues(alpha: 0.8),
                    width: 2,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.fiber_manual_record_rounded,
                    color: kRecordingsHubRec,
                    size: 10,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      s.programmeTitle.isEmpty
                          ? widget.timeText
                          : '${s.channelName} · ${widget.timeText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<DateTime>(
                valueListenable: widget.now,
                builder: (context, current, _) {
                  final until = DateTime.fromMillisecondsSinceEpoch(
                    s.startMs,
                  ).difference(current);
                  final started = until.isNegative;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (started ? kRecordingsHubRec : kRecordingsHubAccent)
                              .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      started ? 'due' : widget.fmtCountdown(until),
                      style: TextStyle(
                        color: started
                            ? kRecordingsHubRec
                            : const Color(0xFFB9A5FF),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.close_rounded,
                size: 17,
                color: Colors.white.withValues(alpha: _focused ? 0.8 : 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
