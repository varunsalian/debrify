import 'dart:async';
import 'dart:io';

import 'package:debrify/features/recording_output/models/share_recording.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_sections.dart';
import 'package:debrify/features/recordings/presentation/recordings_hub_tokens.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter/material.dart';

class RecordingsHubActions {
  RecordingsHubActions(this._deps);
  final RecordingsHubDependencies _deps;
  RecordingsHubSections get _sections => _deps.sections();
  // ── Actions ───────────────────────────────────────────────────────────────
  Future<void> stopAndroid(LiveRecordingStatus rec) async {
    await LiveRecordingService.stop(rec.taskId);
    if (!_deps.mounted()) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      const SnackBar(content: Text('Stopping — saving recording…')),
    );
    // The engine finalizes and publishes off-process; give it a beat, then
    // let the regular poll settle whatever this misses.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (_deps.mounted()) await _sections.data.loadAll();
  }

  Future<void> stopDesktop(DesktopRecordingCapture capture) async {
    final bytes = await capture.stop();
    if (!_deps.mounted()) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
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

  Future<void> cancelSchedule(ScheduledRecording schedule) async {
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
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
    if (confirmed != true || !_deps.mounted()) return;
    if (_sections.data.desktop) {
      await DesktopScheduleService.instance.cancel(schedule.id);
    } else {
      await LiveRecordingService.cancelSchedule(schedule.id);
    }
    // Both cancel paths bump schedulesRevision, whose listener reloads.
  }

  Future<void> play(RecordingLibraryEntry entry) async {
    final display = _sections.format.displayFor(entry);
    await VideoPlayerLauncher.push(
      _deps.context(),
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

  Future<void> delete(RecordingLibraryEntry entry) async {
    final display = _sections.format.displayFor(entry);
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
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
    if (confirmed != true || !_deps.mounted()) return;
    final ok = _sections.data.isAndroid
        ? await LiveRecordingService.deleteRecordingFile(entry.uri)
        : await DesktopRecordingService.deleteRecordingFile(entry.uri);
    if (!_deps.mounted()) return;
    if (!ok) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text("Couldn't delete the recording")),
      );
    }
    await _sections.data.loadAll();
  }

  /// Recording location & timing, then a reload so the footer shows the
  /// chosen folder.
  Future<void> openShareSettings() async {
    final share = _deps.share;
    if (share == null) return;
    await share.openSettings();
    if (!_deps.mounted()) return;
    await _sections.data.loadShare(force: true);
  }

  Future<void> playShare(ShareRecording recording) async {
    final share = _deps.share;
    if (share == null) return;
    final Uri url;
    try {
      url = await share.streamUrl(recording);
    } catch (_) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text("Couldn't open the network share")),
      );
      return;
    }
    if (!_deps.mounted()) return;
    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: url.toString(),
        title: recording.title,
        showVideoTitle: true,
        // The stream is served from inside Debrify for as long as it runs.
        disableExternalPlayer: true,
      ),
    );
  }

  Future<void> deleteShare(ShareRecording recording) async {
    final share = _deps.share;
    final address = _deps.owners.share?.address;
    if (share == null || address == null) return;
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete recording?'),
        content: Text(
          '${recording.title} (${_sections.format.fmtBytes(recording.bytes)}) '
          'will be removed from $address.',
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
    if (confirmed != true || !_deps.mounted()) return;
    try {
      await share.delete(recording);
    } catch (_) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text("Couldn't delete it from the share")),
      );
    }
    if (_deps.mounted()) await _sections.data.loadShare(force: true);
  }

  Future<void> openOutputSettings() async {
    final open = _deps.openOutputSettings;
    if (open == null) return;
    await open();
    if (_deps.mounted()) await _sections.data.loadAll();
  }

  Future<void> openFolder() async {
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
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text('Recordings folder: ${dir.path}')));
    }
  }
}
