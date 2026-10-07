import 'dart:async';
import 'dart:io';

import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_schedule_row.dart';
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
import 'package:flutter/foundation.dart';
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
  List<LiveRecordingStatus> _live = const [];
  List<ScheduledRecording> _schedules = const [];
  List<RecordingLibraryEntry> _library = const [];
  bool _loading = true;
  bool _exactAlarms = true;

  /// Wall clock for elapsed/countdown text. Only ticks while something needs
  /// it; listeners are scoped ValueListenableBuilders around the text alone.
  final ValueNotifier<DateTime> _now = ValueNotifier<DateTime>(DateTime.now());
  Timer? _ticker;

  /// Android: live captures mutate natively (bytes grow, alarms fire, the
  /// engine finalizes) with no in-process signal — poll while anything is
  /// live or could go live, idle otherwise.
  Timer? _poll;

  /// False while the app is paused/hidden. _syncTimers refuses to arm
  /// anything in that state — otherwise a revision bump arriving while
  /// covered (a desktop capture ending with the window minimized) would
  /// silently re-start the clocks the lifecycle handler just stopped.
  bool _appVisible = true;

  /// Battery-optimization nudge: shown only on EVIDENCE — an interrupted
  /// recording newer than the last dismissal, while the app is not excluded
  /// from optimization. TV boxes have no battery; the nudge never shows
  /// there.
  bool _batteryExempt = true;
  int _batteryNudgeDismissedAtMs = 0;
  static const String _batteryNudgeDismissedPref =
      'recording_battery_nudge_dismissed_at';

  /// The first library row's main (play) focus. The folder button sits on
  /// the same right edge as the rows' delete icons, so geometric DOWN from
  /// it would land on the first DELETE — this node lets the button send
  /// DOWN to the card instead.
  final FocusNode _firstLibraryFocus = FocusNode(
    debugLabel: 'recordings_first_library_row',
  );

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _desktop => DesktopScheduleService.instance.isSupported;

  List<DesktopRecordingCapture> get _desktopCaptures =>
      _desktop ? DesktopRecordingService.instance.captures : const [];

  bool get _anythingLive => _live.isNotEmpty || _desktopCaptures.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LiveRecordingService.schedulesRevision.addListener(_onRevision);
    if (_desktop) {
      DesktopRecordingService.instance.revision.addListener(_onRevision);
    }
    unawaited(_loadAll());
    unawaited(
      DevicePreferences.instance().then((prefs) {
        if (!mounted) return;
        final at = prefs.getInt(_batteryNudgeDismissedPref) ?? 0;
        if (at != 0) setState(() => _batteryNudgeDismissedAtMs = at);
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LiveRecordingService.schedulesRevision.removeListener(_onRevision);
    if (_desktop) {
      DesktopRecordingService.instance.revision.removeListener(_onRevision);
    }
    _ticker?.cancel();
    _poll?.cancel();
    _now.dispose();
    _firstLibraryFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appVisible = true;
      // _loadAll re-arms the ticker and poll via _syncTimers.
      unawaited(_loadAll());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Nothing here is visible while the app isn't — on TV that includes
      // the whole time the native player plays a recording over Flutter, so
      // the 1s clock and the 3s native poll must not keep burning under it.
      _appVisible = false;
      _ticker?.cancel();
      _ticker = null;
      _poll?.cancel();
      _poll = null;
    }
  }

  void _onRevision() {
    if (mounted) unawaited(_loadAll());
  }

  bool get _showBatteryNudge =>
      _isAndroid &&
      !PlatformUtil.isAndroidTvCached &&
      !_batteryExempt &&
      _library.any(
        (e) =>
            e.interrupted &&
            (e.interruptedAtMs ?? e.recordedAtMs) > _batteryNudgeDismissedAtMs,
      );

  void _dismissBatteryNudge() {
    final now = DateTime.now().millisecondsSinceEpoch;
    setState(() => _batteryNudgeDismissedAtMs = now);
    unawaited(
      DevicePreferences.instance().then(
        (prefs) => prefs.setInt(_batteryNudgeDismissedPref, now),
      ),
    );
  }

  Future<void> _loadAll() async {
    final results = await Future.wait<Object>([
      _isAndroid
          ? LiveRecordingService.query()
          : Future.value(const <LiveRecordingStatus>[]),
      _desktop
          ? DesktopScheduleService.instance.list().then(
              (list) => list
                  .map((s) => s.toScheduledRecording())
                  .toList(growable: false),
            )
          : (_isAndroid
                ? LiveRecordingService.listSchedules()
                : Future.value(const <ScheduledRecording>[])),
      _isAndroid
          ? LiveRecordingService.queryLibrary()
          : DesktopRecordingService.listLibrary(),
      _isAndroid
          ? LiveRecordingService.exactAlarmsGranted()
          : Future.value(true),
      _isAndroid
          ? LiveRecordingService.isIgnoringBatteryOptimizations()
          : Future.value(true),
    ]);
    if (!mounted) return;
    final live = (results[0] as List<LiveRecordingStatus>)
        .where((r) => r.isRecording)
        .toList(growable: false);
    final schedules = (results[1] as List<ScheduledRecording>).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final library = (results[2] as List<RecordingLibraryEntry>).toList()
      ..sort(
        (a, b) =>
            _displayFor(b).recordedAt.compareTo(_displayFor(a).recordedAt),
      );
    setState(() {
      _live = live;
      _schedules = schedules;
      _library = library;
      _exactAlarms = results[3] as bool;
      _batteryExempt = results[4] as bool;
      _loading = false;
    });
    _syncTimers();
  }

  void _syncTimers() {
    if (!_appVisible) return;
    final needTick = _anythingLive || _schedules.isNotEmpty;
    if (needTick && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        _now.value = DateTime.now();
      });
    } else if (!needTick && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
    // Android live poll: 3s while capturing (bytes + finalize detection),
    // 15s while merely scheduled (an alarm can fire any minute), off idle.
    // The poll is the LIGHT query — the library (whose native call walks the
    // store against the filesystem) only reloads when the live/scheduled
    // sets actually change.
    _poll?.cancel();
    _poll = null;
    if (_isAndroid && (_live.isNotEmpty || _schedules.isNotEmpty)) {
      _poll = Timer.periodic(
        Duration(seconds: _live.isNotEmpty ? 3 : 15),
        (_) => unawaited(_pollLive()),
      );
    }
  }

  /// The poll body: refresh live captures + schedules only. A membership
  /// change (a capture started or finished, a schedule fired) escalates to a
  /// full [_loadAll] so the library picks up the new file too.
  Future<void> _pollLive() async {
    if (!_isAndroid) return;
    final results = await Future.wait<Object>([
      LiveRecordingService.query(),
      LiveRecordingService.listSchedules(),
    ]);
    if (!mounted) return;
    final live = (results[0] as List<LiveRecordingStatus>)
        .where((r) => r.isRecording)
        .toList(growable: false);
    final schedules = (results[1] as List<ScheduledRecording>).toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    final sameSets =
        live.map((r) => r.taskId).toSet().length == _live.length &&
        _live.every((old) => live.any((r) => r.taskId == old.taskId)) &&
        schedules.length == _schedules.length &&
        _schedules.every((old) => schedules.any((s) => s.id == old.id));
    if (!sameSets) {
      await _loadAll();
      return;
    }
    // Same membership: bytes/elapsed only — no timer re-arm (the cadence is
    // a function of membership, which didn't change).
    setState(() {
      _live = live;
      _schedules = schedules;
    });
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
    if (mounted) await _loadAll();
  }

  Future<void> _stopDesktop(DesktopRecordingCapture capture) async {
    final bytes = await capture.stop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          bytes > 0
              ? 'Recording saved (${_fmtBytes(bytes)})'
              : 'Recording stopped — nothing was captured',
        ),
      ),
    );
    await _loadAll();
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
    if (_desktop) {
      await DesktopScheduleService.instance.cancel(schedule.id);
    } else {
      await LiveRecordingService.cancelSchedule(schedule.id);
    }
    // Both cancel paths bump schedulesRevision, whose listener reloads.
  }

  Future<void> _play(RecordingLibraryEntry entry) async {
    final display = _displayFor(entry);
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: entry.uri,
        title: display.title,
        showVideoTitle: true,
        // Android recordings are content:// / file:// URIs other apps were
        // never granted — an external-player intent would just fail to read
        // them. Desktop passes plain paths, which external players handle.
        disableExternalPlayer: _isAndroid,
      ),
    );
  }

  Future<void> _delete(RecordingLibraryEntry entry) async {
    final display = _displayFor(entry);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(
          '${display.title} (${_fmtBytes(entry.bytes)}) will be removed '
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
    final ok = _isAndroid
        ? await LiveRecordingService.deleteRecordingFile(entry.uri)
        : await DesktopRecordingService.deleteRecordingFile(entry.uri);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete the recording")),
      );
    }
    await _loadAll();
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
    if (!_desktop && !await LiveRecordingService.ensureEngineReady()) {
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

    final result = _desktop
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
    await _loadAll();
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

  // ── Formatting ────────────────────────────────────────────────────────────

  String _fmtBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  String _fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _fmtCountdown(Duration untilStart) {
    if (untilStart.inSeconds <= 60) return 'starting…';
    if (untilStart.inMinutes < 60) return 'in ${untilStart.inMinutes}m';
    final h = untilStart.inHours;
    final m = untilStart.inMinutes.remainder(60);
    if (h < 24) return m == 0 ? 'in ${h}h' : 'in ${h}h ${m}m';
    return 'in ${untilStart.inDays}d ${h.remainder(24)}h';
  }

  String _fmtDuration(int ms) {
    final d = Duration(milliseconds: ms);
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    final m = d.inMinutes.remainder(60);
    return m == 0 ? '${d.inHours}h' : '${d.inHours}h ${m}m';
  }

  String _clock(int ms) => MaterialLocalizations.of(context).formatTimeOfDay(
    TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms)),
  );

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    if (d == today) return 'Today';
    if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]} ${d.day}/${d.month}';
  }

  static final RegExp _stampSuffix = RegExp(
    r'_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})(?:_\d+)?$',
  );

  /// Presentation facts for a library entry, derived once per build:
  /// title (file name minus stamp/extension, or the channel name), the best
  /// recorded-at moment (embedded stamp beats file mtime — mtime is the END
  /// of a capture), and a duration (store truth, else mtime − stamp).
  ({String title, String? channel, DateTime recordedAt, int? durationMs})
  _displayFor(RecordingLibraryEntry entry) {
    var base = entry.name;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    DateTime? stamp;
    final match = _stampSuffix.firstMatch(base);
    if (match != null) {
      base = base.substring(0, match.start);
      stamp = DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
    }
    final title = base.replaceAll('_', ' ').trim();
    final fallback = DateTime.fromMillisecondsSinceEpoch(entry.recordedAtMs);
    final recordedAt = stamp ?? fallback;
    var durationMs = entry.durationMs;
    if (durationMs == null && stamp != null) {
      final gap = fallback.difference(stamp).inMilliseconds;
      // Only when mtime is plausibly the capture's end.
      if (gap > 1000 && gap < 12 * 60 * 60 * 1000) durationMs = gap;
    }
    return (
      title: title.isEmpty ? 'Recording' : title,
      channel: entry.channelName,
      recordedAt: recordedAt,
      durationMs: durationMs,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final desktopCaptures = _desktopCaptures;
    final liveCount = _live.length + desktopCaptures.length;
    final totalBytes = _library.fold<int>(0, (sum, e) => sum + e.bytes);
    final empty =
        !_loading && liveCount == 0 && _schedules.isEmpty && _library.isEmpty;

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
                  (!_desktop &&
                      !(_isAndroid && !_exactAlarms) &&
                      liveCount == 0 &&
                      _schedules.isEmpty &&
                      _library.isNotEmpty)
                  ? () => _firstLibraryFocus.requestFocus()
                  : null,
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: kRecordingsHubAccent,
                      ),
                    )
                  : empty
                  ? RecordingsHubEmptyDvr(
                      onSchedule: () => unawaited(_createManualSchedule()),
                      showAlarmBanner: _isAndroid && !_exactAlarms,
                      onOpenAlarmSettings: () => unawaited(
                        LiveRecordingService.openExactAlarmSettings(),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                      children: [
                        if (_isAndroid && !_exactAlarms) ...[
                          RecordingsHubAlarmBanner(
                            onTap: () => unawaited(
                              LiveRecordingService.openExactAlarmSettings(),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_showBatteryNudge) ...[
                          RecordingsHubBatteryBanner(
                            onFix: () => unawaited(
                              LiveRecordingService.requestIgnoreBatteryOptimizations(),
                            ),
                            onDismiss: _dismissBatteryNudge,
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
                              now: _now,
                              bytesOf: () => capture.bytes,
                              fmtBytes: _fmtBytes,
                              fmtElapsed: _fmtElapsed,
                              autofocus: PlatformUtil.isTelevision && i == 0,
                              onStop: () => unawaited(_stopDesktop(capture)),
                            ),
                          for (final (i, rec) in _live.indexed)
                            RecordingsHubLiveCard(
                              channelName: rec.channelName.isEmpty
                                  ? rec.fileName
                                  : rec.channelName,
                              startedAt: DateTime.fromMillisecondsSinceEpoch(
                                rec.startedAtMs,
                              ),
                              now: _now,
                              bytesOf: () => rec.bytes,
                              fmtBytes: _fmtBytes,
                              fmtElapsed: _fmtElapsed,
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
                          chip: _schedules.isEmpty
                              ? null
                              : '${_schedules.length} UPCOMING',
                          chipColor: kRecordingsHubAccent,
                        ),
                        if (_schedules.isEmpty)
                          const RecordingsHubEmptyHint(
                            text:
                                'Nothing scheduled — pick an upcoming '
                                'programme in a channel\'s TV guide, or '
                                'press Schedule above.',
                          )
                        else
                          for (final (i, schedule) in _schedules.indexed)
                            RecordingsHubScheduleRow(
                              schedule: schedule,
                              now: _now,
                              timeText:
                                  '${_dayLabel(DateTime.fromMillisecondsSinceEpoch(schedule.startMs))} · '
                                  '${_clock(schedule.startMs)} – '
                                  '${_clock(schedule.endMs)}',
                              fmtCountdown: _fmtCountdown,
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
                          chip: _library.isEmpty
                              ? null
                              : '${_library.length} · ${_fmtBytes(totalBytes)}',
                          chipColor: Colors.white38,
                          action: _desktop
                              ? RecordingsHubHubIconButton(
                                  icon: Icons.folder_open_rounded,
                                  tooltip: 'Show in folder',
                                  onPressed: () => unawaited(_openFolder()),
                                  onDown: _library.isEmpty
                                      ? null
                                      : () => _firstLibraryFocus.requestFocus(),
                                )
                              : null,
                        ),
                        if (_library.isEmpty)
                          const RecordingsHubEmptyHint(
                            text:
                                'No recordings yet. Focus a live channel '
                                'and press Record, or schedule one — '
                                'finished recordings appear here, ready '
                                'to play.',
                          )
                        else
                          for (final (i, entry) in _library.indexed)
                            Builder(
                              builder: (context) {
                                final display = _displayFor(entry);
                                return RecordingsHubLibraryRow(
                                  focusNode: i == 0 ? _firstLibraryFocus : null,
                                  title: display.title,
                                  subtitle: [
                                    if (display.channel != null &&
                                        display.channel!.isNotEmpty &&
                                        display.channel != display.title)
                                      display.channel!,
                                    '${_dayLabel(display.recordedAt)} '
                                        '${_clock(display.recordedAt.millisecondsSinceEpoch)}',
                                    _fmtBytes(entry.bytes),
                                    if (display.durationMs != null)
                                      _fmtDuration(display.durationMs!),
                                  ].join(' · '),
                                  monogramName:
                                      display.channel?.isNotEmpty == true
                                      ? display.channel!
                                      : display.title,
                                  autofocus:
                                      PlatformUtil.isTelevision &&
                                      liveCount == 0 &&
                                      _schedules.isEmpty &&
                                      i == 0,
                                  onPlay: () => unawaited(_play(entry)),
                                  onDelete: () => unawaited(_delete(entry)),
                                );
                              },
                            ),
                        const SizedBox(height: 20),
                        Text(
                          _desktop
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
