import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/desktop_schedule_service.dart';
import '../../services/live_recording_service.dart';
import '../../widgets/iptv/iptv_startup_channel_picker.dart';
import 'widgets/settings_widgets.dart';

/// Upcoming scheduled recordings: what will record, when, and a way to cancel.
/// Entries live in the NATIVE schedule store (they must fire with no Flutter
/// running), so this page is a thin viewer over the platform channel.
class ScheduledRecordingsPage extends StatefulWidget {
  const ScheduledRecordingsPage({super.key});

  @override
  State<ScheduledRecordingsPage> createState() =>
      _ScheduledRecordingsPageState();
}

class _ScheduledRecordingsPageState extends State<ScheduledRecordingsPage> {
  List<ScheduledRecording> _schedules = const [];
  bool _loading = true;
  bool _exactAlarms = true;

  /// Desktop backend (in-app Dart scheduler) vs Android backend (native
  /// store + exact alarms). Same page, same rows, different truth source.
  bool get _desktop => DesktopScheduleService.instance.isSupported;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final schedules = _desktop
        ? (await DesktopScheduleService.instance.list())
            .map((s) => s.toScheduledRecording())
            .toList(growable: false)
        : await LiveRecordingService.listSchedules();
    final exact = _desktop || await LiveRecordingService.exactAlarmsGranted();
    if (!mounted) return;
    setState(() {
      _schedules = schedules;
      _exactAlarms = exact;
      _loading = false;
    });
  }

  Future<void> _cancel(ScheduledRecording schedule) async {
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
    await _load();
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(day.year, day.month, day.day);
    if (d == today) return 'Today';
    if (d == today.add(const Duration(days: 1))) return 'Tomorrow';
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[d.weekday - 1]} ${d.day}/${d.month}';
  }

  String _timeRange(BuildContext context, ScheduledRecording s) {
    final loc = MaterialLocalizations.of(context);
    String clock(int ms) => loc.formatTimeOfDay(
          TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms)),
        );
    final start = DateTime.fromMillisecondsSinceEpoch(s.startMs);
    return '${_dayLabel(start)} · ${clock(s.startMs)} – ${clock(s.endMs)}';
  }

  /// Manual timer recording: pick a saved channel, a start time and a
  /// duration — no EPG involved. The scheduling backend is exactly the one
  /// the guide uses; a start time in the past (or "now") late-joins within
  /// seconds, which also makes this the fastest way to TEST the whole
  /// alarm → service → capture chain on a device.
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

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 2))),
      helpText: 'Start time',
    );
    if (time == null || !mounted) return;

    final duration = await showDialog<Duration>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Record for how long?'),
        children: [
          for (final (label, d) in const [
            ('5 minutes (test)', Duration(minutes: 5)),
            ('30 minutes', Duration(minutes: 30)),
            ('1 hour', Duration(hours: 1)),
            ('2 hours', Duration(hours: 2)),
            ('3 hours', Duration(hours: 3)),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(d),
              child: Text(label),
            ),
        ],
      ),
    );
    if (duration == null || !mounted) return;

    var start = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // A start at or before "now" means "from right now": the alarm layer
    // late-joins past-start schedules within seconds anyway, so lean into it
    // instead of rejecting the most useful test case.
    final startsImmediately = !start.isAfter(now);
    if (startsImmediately) start = now;
    final end = start.add(duration);

    final result = _desktop
        ? await DesktopScheduleService.instance.add(
            url: recordUrl,
            channelName: choice.name,
            programmeTitle: '',
            startMs: start.millisecondsSinceEpoch,
            endMs: end.millisecondsSinceEpoch,
            headers: choice.httpHeaders,
          )
        : await LiveRecordingService.schedule(
            url: recordUrl,
            channelName: choice.name,
            programmeTitle: '',
            startMs: start.millisecondsSinceEpoch,
            endMs: end.millisecondsSinceEpoch,
            headers: choice.httpHeaders,
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
            'overlap' => 'Overlaps another scheduled recording — desktop '
                'records one channel at a time',
            'bad_time' => 'That time has already passed',
            _ => "Couldn't schedule recording",
          };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled recordings')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_createManualSchedule()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Schedule'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_exactAlarms)
                  Card(
                    color: Colors.amber.withValues(alpha: 0.12),
                    child: ListTile(
                      leading: const Icon(
                        Icons.schedule_rounded,
                        color: Colors.amber,
                      ),
                      title: const Text('Exact alarms are off'),
                      subtitle: const Text(
                        'New recordings can\'t be scheduled, and existing '
                        'ones may not start, until "Alarms & reminders" is '
                        'allowed. Tap to open system settings.',
                      ),
                      onTap: () =>
                          unawaited(LiveRecordingService.openExactAlarmSettings()),
                    ),
                  ),
                if (!_exactAlarms) const SizedBox(height: 12),
                if (_schedules.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          Icon(
                            Icons.fiber_manual_record_rounded,
                            size: 44,
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Nothing scheduled',
                            style: TextStyle(fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pick an upcoming programme in a channel\'s TV '
                            'guide and choose Record — or use Schedule below '
                            'to set a channel and time yourself (starred '
                            'channels only).',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < _schedules.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            autofocus: i == 0,
                            leading: const Icon(
                              Icons.fiber_manual_record_rounded,
                              color: Color(0xFFF43F5E),
                            ),
                            title: Text(
                              _schedules[i].programmeTitle.isEmpty
                                  ? _schedules[i].channelName
                                  : _schedules[i].programmeTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_schedules[i].channelName}\n'
                              '${_timeRange(context, _schedules[i])}',
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.delete_outline_rounded),
                            onTap: () => unawaited(_cancel(_schedules[i])),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                SettingsInfoBanner(
                  text: _desktop
                      // The honest Tier-1 contract — desktop has no
                      // AlarmManager, so a closed app records nothing.
                      ? 'Recordings run while Debrify is open and the '
                            'computer is awake. They save to '
                            'Downloads/Debrify/Recordings.'
                      : 'Recordings run even with the app closed, as long as '
                            'the device is on and connected. They save to '
                            'Downloads/Debrify/Recordings.',
                ),
              ],
            ),
    );
  }
}
