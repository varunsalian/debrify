import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/desktop_recording_service.dart';
import '../../services/desktop_schedule_service.dart';
import '../../services/live_recording_service.dart';
import '../../services/profiles/profile_preferences.dart';
import '../../services/video_player_launcher.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/recording_limit_dialogs.dart';
import '../../widgets/tv_time_picker.dart';
import '../../widgets/iptv/iptv_stage_panel.dart' show IptvMonogram;
import '../../widgets/iptv/iptv_startup_channel_picker.dart';

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
const _kCard = Color(0xFF10142A);
const _kRec = Color(0xFFF43F5E);
const _kGold = Color(0xFFF5C042);
const _kAccent = Color(0xFF8A5CFF);

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
            child: const Text('Delete', style: TextStyle(color: _kRec)),
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
            _HubBar(
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
                      child: CircularProgressIndicator(color: _kAccent),
                    )
                  : empty
                  ? _EmptyDvr(
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
                          _AlarmBanner(
                            onTap: () => unawaited(
                              LiveRecordingService.openExactAlarmSettings(),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_showBatteryNudge) ...[
                          _BatteryBanner(
                            onFix: () => unawaited(
                              LiveRecordingService.requestIgnoreBatteryOptimizations(),
                            ),
                            onDismiss: _dismissBatteryNudge,
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (liveCount > 0) ...[
                          _SectionHeader(
                            label: 'RECORDING NOW',
                            chip: '$liveCount LIVE',
                            chipColor: _kRec,
                          ),
                          for (final (i, capture) in desktopCaptures.indexed)
                            _LiveCard(
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
                            _LiveCard(
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
                        _SectionHeader(
                          label: 'SCHEDULED',
                          chip: _schedules.isEmpty
                              ? null
                              : '${_schedules.length} UPCOMING',
                          chipColor: _kAccent,
                        ),
                        if (_schedules.isEmpty)
                          const _EmptyHint(
                            text:
                                'Nothing scheduled — pick an upcoming '
                                'programme in a channel\'s TV guide, or '
                                'press Schedule above.',
                          )
                        else
                          for (final (i, schedule) in _schedules.indexed)
                            _ScheduleRow(
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
                        _SectionHeader(
                          label: 'LIBRARY',
                          chip: _library.isEmpty
                              ? null
                              : '${_library.length} · ${_fmtBytes(totalBytes)}',
                          chipColor: Colors.white38,
                          action: _desktop
                              ? _HubIconButton(
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
                          const _EmptyHint(
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
                                return _LibraryRow(
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

// ── Top bar ─────────────────────────────────────────────────────────────────

class _HubBar extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onSchedule;

  /// Non-null exactly when no focusable row sits between the hub bar and
  /// the library — the state where geometric DOWN would hit a delete icon.
  final VoidCallback? onScheduleDown;

  const _HubBar({
    required this.onBack,
    required this.onSchedule,
    this.onScheduleDown,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 10),
      child: Row(
        children: [
          _HubIconButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Back',
            onPressed: onBack,
          ),
          const SizedBox(width: 10),
          const Icon(Icons.fiber_manual_record_rounded, color: _kRec, size: 16),
          const SizedBox(width: 8),
          const Text(
            'Recordings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          _HubButton(
            icon: Icons.add_rounded,
            label: 'Schedule',
            filled: true,
            onPressed: onSchedule,
            onDown: onScheduleDown,
          ),
        ],
      ),
    );
  }
}

// ── Sections ────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final String? chip;
  final Color chipColor;
  final Widget? action;
  const _SectionHeader({
    required this.label,
    this.chip,
    required this.chipColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 0, 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          if (chip != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                chip!,
                style: TextStyle(
                  color: chipColor == Colors.white38
                      ? Colors.white.withValues(alpha: 0.55)
                      : chipColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.45),
          fontSize: 12.5,
          height: 1.45,
        ),
      ),
    );
  }
}

// ── Recording-now card ──────────────────────────────────────────────────────

class _LiveCard extends StatelessWidget {
  final String channelName;
  final DateTime startedAt;
  final ValueNotifier<DateTime> now;
  final int Function() bytesOf;
  final String Function(int) fmtBytes;
  final String Function(Duration) fmtElapsed;
  final bool autofocus;
  final VoidCallback onStop;

  const _LiveCard({
    required this.channelName,
    required this.startedAt,
    required this.now,
    required this.bytesOf,
    required this.fmtBytes,
    required this.fmtElapsed,
    required this.autofocus,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kRec.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _kRec.withValues(alpha: 0.07),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          const _RecDot(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<DateTime>(
                  valueListenable: now,
                  builder: (context, current, _) {
                    final elapsed = current.difference(startedAt);
                    final bytes = bytesOf();
                    return Text(
                      '${fmtElapsed(elapsed.isNegative ? Duration.zero : elapsed)}'
                      '${bytes > 0 ? ' · ${fmtBytes(bytes)}' : ''}',
                      style: TextStyle(
                        color: _kRec.withValues(alpha: 0.9),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _HubButton(
            icon: Icons.stop_rounded,
            label: 'Stop',
            danger: true,
            autofocus: autofocus,
            onPressed: onStop,
          ),
        ],
      ),
    );
  }
}

/// The REC dot: pulses on phone/desktop, static on TV (house rule — no new
/// standing animations on TV hardware).
class _RecDot extends StatefulWidget {
  const _RecDot();

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!PlatformUtil.isTelevision) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
        lowerBound: 0.35,
        upperBound: 1.0,
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kRec,
        boxShadow: [
          BoxShadow(color: _kRec.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
    );
    final controller = _controller;
    if (controller == null) return dot;
    return FadeTransition(opacity: controller, child: dot);
  }
}

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

class _ScheduleRowState extends State<_ScheduleRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.schedule;
    final title = s.programmeTitle.isEmpty ? s.channelName : s.programmeTitle;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
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
              color: _focused ? _kGold : Colors.white.withValues(alpha: 0.06),
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
                    color: _kRec.withValues(alpha: 0.8),
                    width: 2,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.fiber_manual_record_rounded,
                    color: _kRec,
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
                      color: (started ? _kRec : _kAccent).withValues(
                        alpha: 0.14,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      started ? 'due' : widget.fmtCountdown(until),
                      style: TextStyle(
                        color: started ? _kRec : const Color(0xFFB9A5FF),
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

// ── Library row ─────────────────────────────────────────────────────────────

class _LibraryRow extends StatefulWidget {
  final FocusNode? focusNode;
  final String title;
  final String subtitle;
  final String monogramName;
  final bool autofocus;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  const _LibraryRow({
    this.focusNode,
    required this.title,
    required this.subtitle,
    required this.monogramName,
    required this.autofocus,
    required this.onPlay,
    required this.onDelete,
  });

  @override
  State<_LibraryRow> createState() => _LibraryRowState();
}

class _LibraryRowState extends State<_LibraryRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _focused
            ? Colors.white.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused ? _kGold : Colors.white.withValues(alpha: 0.06),
          width: _focused ? 1.8 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onFocusChange: (f) => setState(() => _focused = f),
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    isActivateOrSpaceKey(event.logicalKey)) {
                  widget.onPlay();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onTap: widget.onPlay,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                  child: Row(
                    children: [
                      _Thumb(
                        monogramName: widget.monogramName,
                        highlight: _focused,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _RowIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Delete recording',
            onPressed: widget.onDelete,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String monogramName;
  final bool highlight;
  const _Thumb({required this.monogramName, required this.highlight});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A1F3D), Color(0xFF0C0F22)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          IptvMonogram(name: monogramName, size: 26),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highlight
                    ? _kGold
                    : Colors.black.withValues(alpha: 0.55),
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 14,
                color: highlight ? Colors.black : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ─────────────────────────────────────────────────────────────

class _EmptyDvr extends StatelessWidget {
  final VoidCallback onSchedule;
  final bool showAlarmBanner;
  final VoidCallback onOpenAlarmSettings;
  const _EmptyDvr({
    required this.onSchedule,
    required this.showAlarmBanner,
    required this.onOpenAlarmSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
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
                color: _kRec.withValues(alpha: 0.45),
                width: 2.5,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.fiber_manual_record_rounded,
                color: _kRec,
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
          child: _HubButton(
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
        color: _kRec.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kRec.withValues(alpha: 0.3)),
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

class _AlarmBanner extends StatefulWidget {
  final VoidCallback onTap;
  const _AlarmBanner({required this.onTap});

  @override
  State<_AlarmBanner> createState() => _AlarmBannerState();
}

class _AlarmBannerState extends State<_AlarmBanner> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
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
                  ? _kGold
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

// ── Buttons ─────────────────────────────────────────────────────────────────

class _HubButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final bool danger;
  final bool autofocus;
  final VoidCallback onPressed;

  /// Explicit DOWN target — same right-edge geometry trap as
  /// [_HubIconButton.onDown]: without it, DOWN from the hub bar's Schedule
  /// button can land on a library row's DELETE when nothing focusable sits
  /// between them.
  final VoidCallback? onDown;

  const _HubButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.danger = false,
    this.autofocus = false,
    this.onDown,
  });

  @override
  State<_HubButton> createState() => _HubButtonState();
}

class _HubButtonState extends State<_HubButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color fg;
    if (widget.danger) {
      fill = _kRec.withValues(alpha: _focused ? 0.32 : 0.16);
      fg = const Color(0xFFFF8CA3);
    } else if (widget.filled) {
      fill = _kAccent.withValues(alpha: _focused ? 0.42 : 0.22);
      fg = const Color(0xFFD9CBFF);
    } else {
      fill = Colors.white.withValues(alpha: _focused ? 0.12 : 0.06);
      fg = Colors.white.withValues(alpha: 0.85);
    }
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        if (widget.onDown != null &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onDown!();
          return KeyEventResult.handled;
        }
        // Swallow DOWN repeats while redirecting (see _HubIconButton).
        if (widget.onDown != null &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? _kGold : Colors.transparent,
              width: 1.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 17, color: fg),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Explicit DOWN target. The folder button shares the right edge with the
  /// library rows' delete icons, so pure geometry would move DOWN onto a
  /// DELETE — callers pass this to send focus to the row's card instead.
  final VoidCallback? onDown;

  const _HubIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.onDown,
  });

  @override
  State<_HubIconButton> createState() => _HubIconButtonState();
}

class _HubIconButtonState extends State<_HubIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        if (widget.onDown != null &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          widget.onDown!();
          return KeyEventResult.handled;
        }
        // Swallow DOWN repeats while redirecting, so a held key can't slip
        // one event through geometric traversal mid-move.
        if (widget.onDown != null &&
            event.logicalKey == LogicalKeyboardKey.arrowDown) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: _focused ? 0.12 : 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused ? _kGold : Colors.transparent,
                width: 1.8,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _RowIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_RowIconButton> createState() => _RowIconButtonState();
}

class _RowIconButtonState extends State<_RowIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateOrSpaceKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _focused
                  ? _kRec.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: _focused ? _kGold : Colors.transparent,
                width: 1.8,
              ),
            ),
            child: Icon(
              widget.icon,
              size: 17,
              color: _focused
                  ? const Color(0xFFFF8CA3)
                  : Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
