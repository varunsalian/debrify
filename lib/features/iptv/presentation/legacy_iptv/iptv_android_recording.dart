import 'dart:async';
import 'dart:io' show Platform;

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb, mapEquals;
import 'package:flutter/material.dart';

typedef IptvAndroidRecordingDeps = ({
  IptvRecordingState recordingState,
  BuildContext Function() context,
  bool Function() mounted,
  StateSetter setState,
});

class IptvAndroidRecording {
  final IptvAndroidRecordingDeps _deps;
  final IptvRecordingState _recordingState;

  IptvAndroidRecording(this._deps) : _recordingState = _deps.recordingState;

  void armAndroidRecStateRefresh() {
    if (kIsWeb || !Platform.isAndroid || !_recordingState.pageCanRecord) return;
    _recordingState.androidRecStateDebounce?.cancel();
    _recordingState.androidRecStateDebounce = Timer(
      const Duration(milliseconds: 700),
      () {
        unawaited(refreshAndroidRecordingState());
      },
    );
  }

  Future<void> refreshAndroidRecordingState() async {
    if (kIsWeb || !Platform.isAndroid || !_recordingState.pageCanRecord) return;
    final recordings = await LiveRecordingService.query();
    if (!_deps.mounted()) return;
    final fresh = <String, String>{
      for (final r in recordings)
        if (r.isRecording) r.url: r.taskId,
    };
    if (!mapEquals(fresh, _recordingState.androidRecordingsByUrl)) {
      _deps.setState(() {
        _recordingState.androidRecordingsByUrl
          ..clear()
          ..addAll(fresh);
      });
    }
  }

  /// The Android engine task recording [channel], if any (url or Xtream twin).
  String? androidEngineTaskFor(IptvChannel channel) {
    final direct = _recordingState.androidRecordingsByUrl[channel.url];
    if (direct != null) return direct;
    final twin = LiveRecordingService.xtreamTsTwin(channel.url);
    return twin != null ? _recordingState.androidRecordingsByUrl[twin] : null;
  }

  Future<void> stageStopAndroidRecording(
    IptvChannel channel,
    String taskId,
  ) async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    final ok = await LiveRecordingService.stop(taskId);
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _recordingState.androidRecordingsByUrl.removeWhere(
        (_, id) => id == taskId,
      );
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Recording stopped — saving to Downloads/Debrify/Recordings'
              : "Couldn't stop recording",
        ),
      ),
    );
  }
}
