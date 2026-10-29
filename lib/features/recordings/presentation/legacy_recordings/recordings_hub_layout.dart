import 'dart:async';

import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_schedule_row.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_sections.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_buttons.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_chrome.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_empty_states.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_library_row.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_live_card.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

const _kBg = Color(0xFF070A18);

class RecordingsHubLayout {
  RecordingsHubLayout(this._deps);
  final RecordingsHubDependencies _deps;
  RecordingsHubOwners get _owners => _deps.owners;
  RecordingsHubSections get _sections => _deps.sections();
  // ── Build ─────────────────────────────────────────────────────────────────

  Widget build(BuildContext context) {
    final desktopCaptures = _sections.data.desktopCaptures;
    final liveCount = _owners.live.length + desktopCaptures.length;
    final totalBytes = _owners.library.fold<int>(0, (sum, e) => sum + e.bytes);
    final empty =
        !_owners.loading &&
        liveCount == 0 &&
        _owners.schedules.isEmpty &&
        _owners.library.isEmpty;

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            RecordingsHubHubBar(
              onBack: () => Navigator.of(context).maybePop(),
              onSchedule: () =>
                  unawaited(_sections.scheduling.createManualSchedule()),
              onSettings: _deps.openOutputSettings == null
                  ? null
                  : () => unawaited(_sections.actions.openOutputSettings()),
              // Redirect DOWN only when the first focusable below would be a
              // library delete icon: no alarm banner, no live Stop, no
              // schedule rows, and no desktop folder button in between.
              onScheduleDown:
                  (!_sections.data.desktop &&
                      !(_sections.data.isAndroid && !_owners.exactAlarms) &&
                      liveCount == 0 &&
                      _owners.schedules.isEmpty &&
                      _owners.library.isNotEmpty)
                  ? () => _owners.firstLibraryFocus.requestFocus()
                  : null,
            ),
            Expanded(
              child: _owners.loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: kRecordingsHubAccent,
                      ),
                    )
                  : empty
                  ? RecordingsHubEmptyDvr(
                      onSchedule: () => unawaited(
                        _sections.scheduling.createManualSchedule(),
                      ),
                      showAlarmBanner:
                          _sections.data.isAndroid && !_owners.exactAlarms,
                      onOpenAlarmSettings: () => unawaited(
                        LiveRecordingService.openExactAlarmSettings(),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                      children: [
                        if (_sections.data.isAndroid &&
                            !_owners.exactAlarms) ...[
                          RecordingsHubAlarmBanner(
                            onTap: () => unawaited(
                              LiveRecordingService.openExactAlarmSettings(),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_sections.data.showBatteryNudge) ...[
                          RecordingsHubBatteryBanner(
                            onFix: () => unawaited(
                              LiveRecordingService.requestIgnoreBatteryOptimizations(),
                            ),
                            onDismiss: _sections.data.dismissBatteryNudge,
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (liveCount > 0) ...[
                          RecordingsHubSectionHeader(
                            label: 'RECORDING NOW',
                            chip: '$liveCount LIVE',
                            chipColor: kRecordingsHubRec,
                          ),
                          for (final (i, capture) in desktopCaptures.indexed)
                            RecordingsHubLiveCard(
                              channelName: capture.channelName,
                              startedAt: capture.startedAt,
                              now: _owners.now,
                              bytesOf: () => capture.bytes,
                              fmtBytes: _sections.format.fmtBytes,
                              fmtElapsed: _sections.format.fmtElapsed,
                              autofocus: PlatformUtil.isTelevision && i == 0,
                              onStop: () => unawaited(
                                _sections.actions.stopDesktop(capture),
                              ),
                            ),
                          for (final (i, rec) in _owners.live.indexed)
                            RecordingsHubLiveCard(
                              channelName: rec.channelName.isEmpty
                                  ? rec.fileName
                                  : rec.channelName,
                              startedAt: DateTime.fromMillisecondsSinceEpoch(
                                rec.startedAtMs,
                              ),
                              now: _owners.now,
                              bytesOf: () => rec.bytes,
                              fmtBytes: _sections.format.fmtBytes,
                              fmtElapsed: _sections.format.fmtElapsed,
                              autofocus:
                                  PlatformUtil.isTelevision &&
                                  i == 0 &&
                                  desktopCaptures.isEmpty,
                              onStop: () =>
                                  unawaited(_sections.actions.stopAndroid(rec)),
                            ),
                          const SizedBox(height: 18),
                        ],
                        RecordingsHubSectionHeader(
                          label: 'SCHEDULED',
                          chip: _owners.schedules.isEmpty
                              ? null
                              : '${_owners.schedules.length} UPCOMING',
                          chipColor: kRecordingsHubAccent,
                        ),
                        if (_owners.schedules.isEmpty)
                          const RecordingsHubEmptyHint(
                            text:
                                'Nothing scheduled — pick an upcoming '
                                'programme in a channel\'s TV guide, or '
                                'press Schedule above.',
                          )
                        else
                          for (final (i, schedule) in _owners.schedules.indexed)
                            RecordingsHubScheduleRow(
                              schedule: schedule,
                              now: _owners.now,
                              timeText:
                                  '${_sections.format.dayLabel(DateTime.fromMillisecondsSinceEpoch(schedule.startMs))} · '
                                  '${_sections.format.clock(schedule.startMs)} – '
                                  '${_sections.format.clock(schedule.endMs)}',
                              fmtCountdown: _sections.format.fmtCountdown,
                              autofocus:
                                  PlatformUtil.isTelevision &&
                                  liveCount == 0 &&
                                  i == 0,
                              onCancel: () => unawaited(
                                _sections.actions.cancelSchedule(schedule),
                              ),
                            ),
                        const SizedBox(height: 18),
                        RecordingsHubSectionHeader(
                          label: 'LIBRARY',
                          chip: _owners.library.isEmpty
                              ? null
                              : '${_owners.library.length} · ${_sections.format.fmtBytes(totalBytes)}',
                          chipColor: Colors.white38,
                          action: _sections.data.desktop
                              ? RecordingsHubHubIconButton(
                                  icon: Icons.folder_open_rounded,
                                  tooltip: 'Show in folder',
                                  onPressed: () =>
                                      unawaited(_sections.actions.openFolder()),
                                  onDown: _owners.library.isEmpty
                                      ? null
                                      : () => _owners.firstLibraryFocus
                                            .requestFocus(),
                                )
                              : null,
                        ),
                        if (_owners.library.isEmpty)
                          const RecordingsHubEmptyHint(
                            text:
                                'No recordings yet. Focus a live channel '
                                'and press Record, or schedule one — '
                                'finished recordings appear here, ready '
                                'to play.',
                          )
                        else
                          for (final (i, entry) in _owners.library.indexed)
                            Builder(
                              builder: (context) {
                                final display = _sections.format.displayFor(
                                  entry,
                                );
                                return RecordingsHubLibraryRow(
                                  focusNode: i == 0
                                      ? _owners.firstLibraryFocus
                                      : null,
                                  title: display.title,
                                  subtitle: [
                                    if (display.channel != null &&
                                        display.channel!.isNotEmpty &&
                                        display.channel != display.title)
                                      display.channel!,
                                    '${_sections.format.dayLabel(display.recordedAt)} '
                                        '${_sections.format.clock(display.recordedAt.millisecondsSinceEpoch)}',
                                    _sections.format.fmtBytes(entry.bytes),
                                    if (display.durationMs != null)
                                      _sections.format.fmtDuration(
                                        display.durationMs!,
                                      ),
                                  ].join(' · '),
                                  monogramName:
                                      display.channel?.isNotEmpty == true
                                      ? display.channel!
                                      : display.title,
                                  autofocus:
                                      PlatformUtil.isTelevision &&
                                      liveCount == 0 &&
                                      _owners.schedules.isEmpty &&
                                      i == 0,
                                  onPlay: () =>
                                      unawaited(_sections.actions.play(entry)),
                                  onDelete: () => unawaited(
                                    _sections.actions.delete(entry),
                                  ),
                                );
                              },
                            ),
                        const SizedBox(height: 20),
                        Text(
                          _sections.data.desktop
                              ? 'Recordings run while Debrify is open and '
                                    'the computer is awake · saved in '
                                    'Downloads/Debrify/Recordings'
                              : 'Recordings run even with the app closed '
                                    '· saved in Downloads/Debrify/Recordings',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
