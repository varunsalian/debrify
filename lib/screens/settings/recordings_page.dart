import 'dart:async';
import 'dart:io';

import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart';
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
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/iptv/iptv_startup_channel_picker.dart';
import 'package:debrify/widgets/recording_limit_dialogs.dart';
import 'package:debrify/widgets/tv_time_picker.dart';
import 'package:flutter/material.dart';

// The DVR's front door — three zones on one page:
//   RECORDING NOW  live captures with a Stop button each
//   SCHEDULED      upcoming recordings + the manual channel/time/duration flow
//   LIBRARY        every finished recording, playable in-app with one press
//
// Styled with the IPTV cockpit's tokens (this page belongs to the DVR world,
// not settings-Material). One 1s wall-clock notifier drives elapsed timers and
// countdown chips through scoped ValueListenableBuilders — never a whole-page
// rebuild per second — and it only runs while something is live or scheduled.

const _kBg = Color(0xFF070A18);

/// Lines a dialog row up with the dialog's own title inset.
const _kDialogRowPadding = EdgeInsets.symmetric(horizontal: 24);

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});

  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage>
    with WidgetsBindingObserver {
  final _owners = RecordingsHubOwners();
  RecordingsHubSections? _composition;
  RecordingsHubSections get _sections => _composition ??= RecordingsHubSections(
    RecordingsHubDependencies(
      owners: _owners,
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      sections: () => _sections,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LiveRecordingService.schedulesRevision.addListener(_onRevision);
    if (_sections.data.desktop) {
      DesktopRecordingService.instance.revision.addListener(_onRevision);
    }
    unawaited(_sections.data.loadAll());
    unawaited(
      DevicePreferences.instance().then((prefs) {
        if (!mounted) return;
        final at =
            prefs.getInt(RecordingsHubData.batteryNudgeDismissedPref) ?? 0;
        if (at != 0) setState(() => _owners.batteryNudgeDismissedAtMs = at);
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LiveRecordingService.schedulesRevision.removeListener(_onRevision);
    if (_sections.data.desktop) {
      DesktopRecordingService.instance.revision.removeListener(_onRevision);
    }
    _owners.ticker?.cancel();
    _owners.poll?.cancel();
    _owners.now.dispose();
    _owners.firstLibraryFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _owners.appVisible = true;
      // _loadAll re-arms the ticker and poll via _syncTimers.
      unawaited(_sections.data.loadAll());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Nothing here is visible while the app isn't — on TV that includes
      // the whole time the native player plays a recording over Flutter, so
      // the 1s clock and the 3s native poll must not keep burning under it.
      _owners.appVisible = false;
      _owners.ticker?.cancel();
      _owners.ticker = null;
      _owners.poll?.cancel();
      _owners.poll = null;
    }
  }

  void _onRevision() {
    if (mounted) unawaited(_sections.data.loadAll());
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _stopAndroid(LiveRecordingStatus rec) async {
    await LiveRecordingService.stop(rec.taskId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stopping — saving recording…')),
    );
    // The engine finalizes and publishes off-process; give it a beat, then
    // let the regular poll settle whatever this misses.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) await _sections.data.loadAll();
  }

  Future<void> _stopDesktop(DesktopRecordingCapture capture) async {
    final bytes = await capture.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bytes > 0
              ? 'Recording saved (${_sections.format.fmtBytes(bytes)})'
              : 'Recording stopped — nothing was captured',
        ),
      ),
    );
    await _sections.data.loadAll();
  }

  Future<void> _cancelSchedule(ScheduledRecording schedule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel recording?'),
        content: Text(
          schedule.programmeTitle.isEmpty
              ? schedule.channelName
              : '${schedule.programmeTitle} — ${schedule.channelName}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel recording'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (_sections.data.desktop) {
      await DesktopScheduleService.instance.cancel(schedule.id);
    } else {
      await LiveRecordingService.cancelSchedule(schedule.id);
    }
    // Both cancel paths bump schedulesRevision, whose listener reloads.
  }

  Future<void> _play(RecordingLibraryEntry entry) async {
    final display = _sections.format.displayFor(entry);
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: entry.uri,
        title: display.title,
        showVideoTitle: true,
        // Android recordings are content:// / file:// URIs other apps were
        // never granted — an external-player intent would just fail to read
        // them. Desktop passes plain paths, which external players handle.
        disableExternalPlayer: _sections.data.isAndroid,
      ),
    );
  }

  Future<void> _delete(RecordingLibraryEntry entry) async {
    final display = _sections.format.displayFor(entry);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(
          '${display.title} (${_sections.format.fmtBytes(entry.bytes)}) will be removed '
          'from this device.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: kRecordingsHubRec),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = _sections.data.isAndroid
        ? await LiveRecordingService.deleteRecordingFile(entry.uri)
        : await DesktopRecordingService.deleteRecordingFile(entry.uri);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete the recording")),
      );
    }
    await _sections.data.loadAll();
  }

  Future<void> _openFolder() async {
    final dir = await DesktopRecordingService.recordingsDir();
    try {
      await dir.create(recursive: true);
      if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [dir.path]);
      } else {
        await Process.run('xdg-open', [dir.path]);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recordings folder: ${dir.path}')));
    }
  }

  /// Manual timer recording — ported from the original Scheduled page: pick a
  /// saved channel, a start time and a duration; a start in the past (or
  /// "now") late-joins within seconds.
  Future<void> _createManualSchedule() async {
    if (!_sections.data.desktop &&
        !await LiveRecordingService.ensureEngineReady()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Storage access is needed to save recordings'),
        ),
      );
      return;
    }
    if (!mounted) return;
    final choice = await showIptvStartupChannelPicker(
      context,
      title: 'Record which channel?',
    );
    if (choice == null || !mounted) return;

    if (!LiveRecordingService.isSchedulableUrl(choice.url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "This channel can't be scheduled — recording needs a direct "
            'TS or Xtream stream',
          ),
        ),
      );
      return;
    }
    final recordUrl = LiveRecordingService.engineRecordableUrl(choice.url);
    if (recordUrl == null) return;

    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
      helpText: 'Recording date',
    );
    if (date == null || !mounted) return;

    final time = await _pickTime(
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 2))),
      helpText: 'Start time',
    );
    if (time == null || !mounted) return;

    var start = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final startsImmediately = !start.isAfter(now);
    if (startsImmediately) start = now;

    final duration = await _askRecordingLength(start);
    if (duration == null || !mounted) return;
    final end = start.add(duration);

    // Conflict gate — no Manage button here: the rows to stop or cancel are
    // right behind the dialog.
    if (!await ensureRecordingCapacity(
      context,
      startMs: start.millisecondsSinceEpoch,
      endMs: end.millisecondsSinceEpoch,
      candidateUrl: recordUrl,
      offerManage: false,
    )) {
      return;
    }
    if (!mounted) return;

    final result = _sections.data.desktop
        ? await DesktopScheduleService.instance.add(
            url: recordUrl,
            channelName: choice.name,
            programmeTitle: '',
            startMs: start.millisecondsSinceEpoch,
            endMs: end.millisecondsSinceEpoch,
            headers: choice.httpHeaders,
            connectionResourceId: choice.connectionResourceId,
            resourceAuthorizationRevision: choice.connectionResourceRevision,
          )
        : await LiveRecordingService.schedule(
            url: recordUrl,
            channelName: choice.name,
            programmeTitle: '',
            startMs: start.millisecondsSinceEpoch,
            endMs: end.millisecondsSinceEpoch,
            headers: choice.httpHeaders,
            connectionResourceId: choice.connectionResourceId,
            resourceAuthorizationRevision: choice.connectionResourceRevision,
          );
    if (!mounted) return;
    if (result.errorCode == 'exact_alarms_required') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Allow "Alarms & reminders" for Debrify to schedule recordings',
          ),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () =>
                unawaited(LiveRecordingService.openExactAlarmSettings()),
          ),
        ),
      );
      return;
    }
    final message = result.ok
        ? (startsImmediately
              ? 'Recording starts in a few seconds'
              : 'Recording scheduled')
        : switch (result.errorCode) {
            'duplicate' => 'Already scheduled at that time',
            'overlap' =>
              'Would exceed the simultaneous-recordings limit — raise it '
                  'in IPTV settings or pick another slot',
            'bad_time' => 'That time has already passed',
            _ => "Couldn't schedule recording",
          };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    await _sections.data.loadAll();
  }

  /// Material's time picker can't be driven by a remote — its dial isn't
  /// focusable and its keyboard mode is a raw TextField — so TV gets the
  /// spinner instead. Everything else keeps the platform picker.
  Future<TimeOfDay?> _pickTime({
    required TimeOfDay initialTime,
    required String helpText,
  }) {
    if (PlatformUtil.isAndroidTvCached) {
      return showTvTimePicker(
        context: context,
        initialTime: initialTime,
        helpText: helpText,
      );
    }
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: helpText,
    );
  }

  /// How long to record, asked as a length. The presets cover the common cases
  /// in one tap; "Pick end time…" opens the same clock the start time uses, for
  /// when the programme's END is the thing you actually know. Returns null if
  /// either step is dismissed.
  Future<Duration?> _askRecordingLength(DateTime start) async {
    // Pops either a Duration (preset) or true (go to the clock).
    final choice = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Record for how long?'),
        children: [
          // ListTile, not SimpleDialogOption: the latter can't autofocus, so on
          // TV the remote had no landing spot in this dialog at all.
          for (final (i, (label, d)) in const [
            ('5 minutes (test)', Duration(minutes: 5)),
            ('30 minutes', Duration(minutes: 30)),
            ('1 hour', Duration(hours: 1)),
            ('2 hours', Duration(hours: 2)),
            ('3 hours', Duration(hours: 3)),
          ].indexed)
            ListTile(
              autofocus: PlatformUtil.isAndroidTvCached && i == 0,
              contentPadding: _kDialogRowPadding,
              title: Text(label),
              onTap: () => Navigator.of(dialogContext).pop(d),
            ),
          const Divider(height: 12),
          ListTile(
            contentPadding: _kDialogRowPadding,
            leading: const Icon(Icons.schedule_outlined, size: 20),
            horizontalTitleGap: 10,
            minLeadingWidth: 0,
            title: const Text('Pick end time…'),
            onTap: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return null;
    if (choice is Duration) return choice;

    final endTime = await _pickTime(
      initialTime: TimeOfDay.fromDateTime(start.add(const Duration(hours: 1))),
      helpText: 'End time',
    );
    if (endTime == null || !mounted) return null;

    var end = DateTime(
      start.year,
      start.month,
      start.day,
      endTime.hour,
      endTime.minute,
    );
    // An end at or before the start reads as tomorrow — the late-night
    // programme that runs past midnight, which is exactly when someone wants
    // to name the end instead of counting hours. Roll the calendar day rather
    // than adding 24h so the clock still reads what was picked across a DST
    // change.
    if (!end.isAfter(start)) {
      end = DateTime(
        start.year,
        start.month,
        start.day + 1,
        endTime.hour,
        endTime.minute,
      );
    }
    final length = end.difference(start);

    // The presets top out at 3h, so an all-day recording can only come from
    // here — usually a mis-set clock that rolled a few minutes into tomorrow.
    // Long recordings are legitimate (sport, overnight), so confirm, don't cap.
    if (length > const Duration(hours: 6)) {
      final hours = length.inHours;
      final minutes = length.inMinutes.remainder(60);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text("That's a long recording"),
          content: Text(
            'Recording would run ${hours}h'
            '${minutes > 0 ? ' ${minutes}m' : ''}, '
            'ending ${TimeOfDay.fromDateTime(end).format(dialogContext)}'
            '${end.day != start.day ? ' the next day' : ''}.',
          ),
          actions: [
            // Safe choice holds focus, like the delete dialog above: on TV
            // this guard exists to catch a mis-set clock, so confirming
            // should take a deliberate move rather than a reflex OK.
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Record'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return null;
    }
    return length;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
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
              onSchedule: () => unawaited(_createManualSchedule()),
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
                      onSchedule: () => unawaited(_createManualSchedule()),
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
                              onStop: () => unawaited(_stopDesktop(capture)),
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
                              onStop: () => unawaited(_stopAndroid(rec)),
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
                              onCancel: () =>
                                  unawaited(_cancelSchedule(schedule)),
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
                                  onPressed: () => unawaited(_openFolder()),
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
                                  onPlay: () => unawaited(_play(entry)),
                                  onDelete: () => unawaited(_delete(entry)),
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
