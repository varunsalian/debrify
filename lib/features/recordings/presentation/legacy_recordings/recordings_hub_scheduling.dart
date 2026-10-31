import 'dart:async';

import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_sections.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/iptv/iptv_startup_channel_picker.dart';
import 'package:debrify/widgets/recording_limit_dialogs.dart';
import 'package:debrify/widgets/tv_time_picker.dart';
import 'package:flutter/material.dart';

/// Lines a dialog row up with the dialog's own title inset.
const _kDialogRowPadding = EdgeInsets.symmetric(horizontal: 24);

class RecordingsHubScheduling {
  RecordingsHubScheduling(this._deps);
  final RecordingsHubDependencies _deps;
  RecordingsHubSections get _sections => _deps.sections();

  /// Manual timer recording — ported from the original Scheduled page: pick a
  /// saved channel, a start time and a duration; a start in the past (or
  /// "now") late-joins within seconds.
  Future<void> createManualSchedule() async {
    if (!_sections.data.desktop &&
        !await LiveRecordingService.ensureEngineReady()) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Text('Storage access is needed to save recordings'),
        ),
      );
      return;
    }
    if (!_deps.mounted()) return;
    final choice = await showIptvStartupChannelPicker(
      _deps.context(),
      title: 'Record which channel?',
    );
    if (choice == null || !_deps.mounted()) return;

    if (!LiveRecordingService.isSchedulableUrl(choice.url)) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
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
      context: _deps.context(),
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 7)),
      helpText: 'Recording date',
    );
    if (date == null || !_deps.mounted()) return;

    final time = await _pickTime(
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 2))),
      helpText: 'Start time',
    );
    if (time == null || !_deps.mounted()) return;

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
    if (duration == null || !_deps.mounted()) return;
    final end = start.add(duration);

    // Conflict gate — no Manage button here: the rows to stop or cancel are
    // right behind the dialog.
    if (!await ensureRecordingCapacity(
      _deps.context(),
      startMs: start.millisecondsSinceEpoch,
      endMs: end.millisecondsSinceEpoch,
      candidateUrl: recordUrl,
      offerManage: false,
    )) {
      return;
    }
    if (!_deps.mounted()) return;

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
    if (!_deps.mounted()) return;
    if (result.errorCode == 'exact_alarms_required') {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: const Text(
            'Allow "Alarms & reminders" for Debrify to schedule recordings',
          ),
          persist: false, // auto-hide, as before Flutter 3.44
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
      _deps.context(),
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
        context: _deps.context(),
        initialTime: initialTime,
        helpText: helpText,
      );
    }
    return showTimePicker(
      context: _deps.context(),
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
      context: _deps.context(),
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
    if (choice == null || !_deps.mounted()) return null;
    if (choice is Duration) return choice;

    final endTime = await _pickTime(
      initialTime: TimeOfDay.fromDateTime(start.add(const Duration(hours: 1))),
      helpText: 'End time',
    );
    if (endTime == null || !_deps.mounted()) return null;

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
        context: _deps.context(),
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
      if (confirmed != true || !_deps.mounted()) return null;
    }
    return length;
  }
}
