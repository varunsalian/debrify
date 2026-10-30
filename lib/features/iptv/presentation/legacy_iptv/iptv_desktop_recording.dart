import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter/material.dart';

typedef IptvDesktopRecordingDeps = ({
  BuildContext Function() context,
  bool Function() mounted,
  StateSetter setState,
});

class IptvDesktopRecording {
  final IptvDesktopRecordingDeps _deps;

  IptvDesktopRecording(this._deps);

  /// The desktop capture currently recording [channel], if any — matched on
  /// the channel's URL or its Xtream `.ts` twin. Drives the stage's
  /// Record↔Stop button: with no notifications on desktop, that button is a
  /// page-started capture's ONLY stop surface.
  DesktopRecordingCapture? desktopCaptureFor(IptvChannel channel) {
    final service = DesktopRecordingService.instance;
    final direct = service.captureForUrl(channel.url);
    if (direct != null) return direct;
    final twin = LiveRecordingService.xtreamTsTwin(channel.url);
    return twin != null ? service.captureForUrl(twin) : null;
  }

  Future<void> stageStopDesktopRecording(
    DesktopRecordingCapture capture,
  ) async {
    final messenger = ScaffoldMessenger.of(_deps.context());
    final bytes = await capture.stop();
    // After the stop: a share that fails the last write moves it locally.
    final savedPath = capture.savedTo;
    if (!_deps.mounted()) return;
    _deps.setState(() {}); // flip the stage button back to Record
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          bytes > 0
              ? 'Recording saved: $savedPath'
              : 'Recording failed — nothing was captured',
        ),
      ),
    );
  }
}
