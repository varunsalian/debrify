import 'dart:async';
import 'dart:io';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/widgets/recording_limit_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpIptvRecordingHost {
  void setState(VoidCallback fn);
  BuildContext get context;
  bool get mounted;
  IptvChannel? get currentIptvChannel;
  Future<({String id, int revision})?> currentRecordingResource();
  DesktopRecordingCapture? desktopCaptureForCurrent();
  bool get engineFlagOn;
  Future<String?> engineRecordUrlForCurrent();
  String? get engineTaskId;
  set engineTaskId(String? v);
  bool get iptvZapBannerOwnsIdentity;
  bool get isRecording;
  set isRecording(bool v);
  mk.Player get player;
  bool get playerCreated;
  String? playingLiveUrl(IptvChannel channel);
  String recordingFileName(String channelName);
  int get recordingStartGen;
  set recordingStartGen(int v);
  bool get recordingSupported;
  Future<String> recordingTargetPath(
    String channelName, {
    String extension = 'mkv',
  });
  String? get recordingTempPath;
  set recordingTempPath(String? v);
  void tapMpvLogsForRecording();
  void untapMpvLogs();
  bool get isIOS;
}

class VpIptvRecording {
  VpIptvRecording(this._host);
  final VpIptvRecordingHost _host;

  /// Supersedes stale engine-state refreshes (zap during a query round-trip).
  int engineRefreshTicket = 0;

  /// Record is offered only for live IPTV on a libmpv backend.
  bool get canRecord =>
      _host.recordingSupported && _host.iptvZapBannerOwnsIdentity;

  Future<void> toggleRecording() async {
    // Desktop capture of the current channel: stop it.
    final desktopCapture = _host.desktopCaptureForCurrent();
    if (desktopCapture != null) {
      final savedPath = desktopCapture.path;
      final bytes = await desktopCapture.stop();
      if (!_host.mounted) return;
      // The revision listener has already repainted (the capture ended during
      // that await); this only guarantees it for the pathological case where
      // the notification was swallowed.
      _host.setState(() {});
      ScaffoldMessenger.of(_host.context).showSnackBar(
        SnackBar(
          content: Text(
            bytes > 0
                ? 'Recording saved: $savedPath'
                : 'Recording failed — nothing was captured',
          ),
        ),
      );
      return;
    }
    // Engine capture of the current channel: stop it. Finalization is async in
    // the service; its "Saved" notification is the confirmation.
    final engineTask = _host.engineTaskId;
    if (engineTask != null) {
      _host.setState(() => _host.engineTaskId = null);
      final ok = await LiveRecordingService.stop(engineTask);
      if (!_host.mounted) return;
      ScaffoldMessenger.of(_host.context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Recording stopped — saving to Downloads/Debrify/Recordings'
                : "Couldn't stop recording",
          ),
        ),
      );
      return;
    }
    if (_host.isRecording) {
      await stopRecording();
      return;
    }
    // Engine first on Android: its capture survives zaps, Home, even the app
    // dying. The tee stays as the fallback — and as the only recorder for true
    // HLS, which mpv can capture but the engine cannot.
    if (Platform.isAndroid && _host.engineFlagOn && _host.recordingSupported) {
      final channel = _host.currentIptvChannel;
      final recordUrl = await _host.engineRecordUrlForCurrent();
      if (channel != null && recordUrl != null) {
        if (!await ensureRecordingCapacity(_host.context)) return;
        if (!_host.mounted) return;
        // This path skips ensureEngineReady (support was pre-checked), so
        // the one-time notification ask lives here explicitly — fire-and-
        // forget, so an unanswered dialog can't delay the capture.
        unawaited(LiveRecordingService.ensureNotificationPermission());
        final resource = await _host.currentRecordingResource();
        if (!_host.mounted) return;
        final result = await LiveRecordingService.start(
          url: recordUrl,
          fileName: _host.recordingFileName(channel.name),
          channelName: channel.name,
          headers: channel.playbackHeaders,
          connectionResourceId: resource?.id,
          resourceAuthorizationRevision: resource?.revision,
        );
        if (!_host.mounted) return;
        if (result.ok) {
          _host.setState(() => _host.engineTaskId = result.id);
          ScaffoldMessenger.of(_host.context).showSnackBar(
            const SnackBar(
              content: Text(
                'Recording in background — keeps going if you zap or leave. '
                'Stop from here or the notification.',
              ),
            ),
          );
        } else if (result.errorCode == 'recording_limit_reached') {
          ScaffoldMessenger.of(_host.context).showSnackBar(
            const SnackBar(
              content: Text(
                'Recording limit reached — free a slot or raise the limit '
                'in IPTV settings',
              ),
            ),
          );
        } else if (!ProfileRuntime.isProfileCommitted &&
            (result.errorCode == 'engine_unsupported' ||
                result.errorCode == 'fgs_not_allowed' ||
                result.errorCode == 'missing_plugin')) {
          // Engine unreachable: the tee still works, with its semantics.
          await startRecording();
        } else {
          ScaffoldMessenger.of(_host.context).showSnackBar(
            const SnackBar(content: Text("Couldn't start recording")),
          );
        }
        return;
      }
      // recordUrl == null: true segmented stream (no Xtream twin) — only the
      // tee can capture what mpv is demuxing. Fall through.
      if (ProfileRuntime.isProfileCommitted) {
        ScaffoldMessenger.of(_host.context).showSnackBar(
          const SnackBar(
            content: Text('This stream cannot be recorded safely'),
          ),
        );
        return;
      }
    }
    // Desktop: the raw HTTP capture is the ONLY recorder that works — the mpv
    // tee is dead on media_kit's stock libs (no muxers in its FFmpeg). Never
    // fall through to the tee here; for unrecordable streams say so instead
    // of starting something that provably writes nothing.
    if (DesktopRecordingService.instance.isSupported &&
        !_host.isIOS &&
        _host.recordingSupported) {
      final channel = _host.currentIptvChannel;
      final recordUrl = await _host.engineRecordUrlForCurrent();
      if (channel == null) return;
      if (recordUrl == null) {
        ScaffoldMessenger.of(_host.context).showSnackBar(
          const SnackBar(
            content: Text(
              "This channel can't be recorded on desktop (HLS stream)",
            ),
          ),
        );
        return;
      }
      if (!await ensureRecordingCapacity(_host.context)) return;
      if (!_host.mounted) return;
      // Raw byte copy → the capture IS a transport stream: .ts, not the
      // tee's .mkv.
      final path = await _host.recordingTargetPath(
        channel.name,
        extension: 'ts',
      );
      // The screen may have closed during that await. Starting now would be
      // legitimate — captures outlive this screen — but the state below can't
      // be set on a dead widget, and the user asked for this from a surface
      // that is gone.
      if (!_host.mounted) return;
      // No onFinished: endings are announced app-wide by the reporter in
      // main(), which is still alive when this screen isn't, and the revision
      // listener repaints the button. A screen-scoped callback would only
      // duplicate the toast while the player happens to be open.
      final resource = await _host.currentRecordingResource();
      if (!_host.mounted) return;
      final capture = await DesktopRecordingService.instance.start(
        url: recordUrl,
        path: path,
        channelName: channel.name,
        headers: channel.playbackHeaders,
        connectionResourceId: resource?.id,
        resourceAuthorizationRevision: resource?.revision,
      );
      if (!_host.mounted) return;
      if (capture == null) {
        ScaffoldMessenger.of(_host.context).showSnackBar(
          const SnackBar(content: Text("Couldn't start recording")),
        );
        return;
      }
      _host.setState(() {});
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(
          content: Text(
            'Recording in background — keeps going if you zap or leave. '
            'Stop from here or Settings → Recordings.',
          ),
        ),
      );
      return;
    }
    await startRecording();
  }

  /// Re-derive [_engineTaskId] from the native registry — a capture may have
  /// been started in an earlier player session, or stopped from the
  /// notification while this screen was open.
  Future<void> refreshEngineRecordingState() async {
    if (!Platform.isAndroid || !_host.engineFlagOn) return;
    final channel = _host.currentIptvChannel;
    if (channel == null || channel.isLive != true) {
      if (_host.engineTaskId != null && _host.mounted) {
        _host.setState(() => _host.engineTaskId = null);
      }
      return;
    }
    final ticket = ++engineRefreshTicket;
    final playing = _host.playingLiveUrl(channel);
    if (playing == null) {
      if (_host.engineTaskId != null) {
        _host.setState(() => _host.engineTaskId = null);
      }
      return;
    }
    final twin = LiveRecordingService.xtreamTsTwin(playing);
    final recordings = await LiveRecordingService.query();
    if (!_host.mounted || ticket != engineRefreshTicket) return;
    String? found;
    for (final r in recordings) {
      if (r.isRecording &&
          (r.url == playing || (twin != null && r.url == twin))) {
        found = r.taskId;
        break;
      }
    }
    if (found != _host.engineTaskId) {
      _host.setState(() => _host.engineTaskId = found);
    }
  }

  Future<void> startRecording() async {
    if (!_host.playerCreated) return;
    final platform = _host.player.platform;
    if (platform is! mk.NativePlayer) return;
    final channel = _host.currentIptvChannel;
    if (channel == null) return;
    final gen = ++_host.recordingStartGen;
    try {
      final path = await _host.recordingTargetPath(channel.name);
      final parent = Directory(path).parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      // The channel (or the whole screen) may have gone while the storage work
      // ran. Arming now would tee the NEW stream into the old channel's file.
      if (gen != _host.recordingStartGen ||
          !_host.mounted ||
          !_host.playerCreated) {
        return;
      }
      _host.tapMpvLogsForRecording();
      await platform.setProperty('stream-record', path);
      // Read the property back: proves whether mpv actually ACCEPTED the
      // target (a silent internal failure leaves it set but writes nothing —
      // the log tap above catches that case).
      var echoed = '';
      try {
        echoed = await platform.getProperty('stream-record');
      } catch (_) {}
      debugPrint(
        'VideoPlayer: stream-record armed — mpv reports "$echoed" '
        '(want "$path")',
      );
      if (gen != _host.recordingStartGen || !_host.mounted) {
        // Lost the race inside setProperty itself: disarm rather than leave an
        // untracked recording running on someone else's stream.
        _host.untapMpvLogs();
        await disarmStrayRecording(platform, path);
        return;
      }
      _host.setState(() {
        _host.isRecording = true;
        _host.recordingTempPath = path;
      });
      // Crash insurance: registered natively so the file gets published on
      // next launch even if this process never reaches stopRecording.
      if (Platform.isAndroid) {
        unawaited(
          AndroidNativeDownloader.registerPendingRecording(
            path: path,
            fileName: path.split(Platform.pathSeparator).last,
            mimeType: 'video/x-matroska',
          ),
        );
      }
      ScaffoldMessenger.of(_host.context).showSnackBar(
        SnackBar(
          content: Text(
            // The tee records what the player reads, so on Android (where the
            // engine exists as the contrast) say the semantics out loud.
            Platform.isAndroid
                ? 'Recording started (stops if you leave the channel)'
                : 'Recording started',
          ),
        ),
      );
    } catch (e) {
      _host.untapMpvLogs();
      debugPrint('VideoPlayer: start recording failed: $e');
      if (!_host.mounted) return;
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(content: Text('Could not start recording')),
      );
    }
  }

  /// Undo a recording that got armed after its channel or screen went away.
  /// The stub file is milliseconds old, so dropping it loses nothing a user
  /// would recognise as a recording.
  Future<void> disarmStrayRecording(
    mk.NativePlayer platform,
    String path,
  ) async {
    try {
      await platform.setProperty('stream-record', '');
    } catch (e) {
      debugPrint('VideoPlayer: disarm stray recording failed: $e');
    }
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('VideoPlayer: stray recording cleanup failed: $e');
    }
  }

  /// Stop the active recording. Auto-stops (channel change / dispose) pass
  /// [userInitiated] = false to stay quiet.
  Future<void> stopRecording({bool userInitiated = true}) async {
    // A stop supersedes an in-flight start too — including one that has not
    // yet flipped `_isRecording` and so is invisible to the check below.
    _host.recordingStartGen++;
    if (!_host.isRecording) return;
    final path = _host.recordingTempPath;
    final platform = _host.playerCreated ? _host.player.platform : null;
    // Flip state first so a rapid re-tap / channel switch can't double-stop.
    if (_host.mounted) {
      _host.setState(() {
        _host.isRecording = false;
        _host.recordingTempPath = null;
      });
    } else {
      _host.isRecording = false;
      _host.recordingTempPath = null;
    }
    try {
      if (platform is mk.NativePlayer) {
        await platform.setProperty('stream-record', '');
      }
    } catch (e) {
      debugPrint('VideoPlayer: stop recording failed: $e');
    }
    _host.untapMpvLogs();
    if (path == null) return;
    // VERIFY before claiming anything: mpv can accept `stream-record` and
    // still write nothing (internal fopen refused, undumpable demuxer) — the
    // first macOS test hit exactly that, with a "saved" message over an empty
    // folder.
    var fileBytes = 0;
    try {
      final file = File(path);
      if (await file.exists()) fileBytes = await file.length();
    } catch (_) {}
    debugPrint(
      'VideoPlayer: tee recording stopped — $fileBytes bytes on disk at $path',
    );
    final fileOk = fileBytes > 0;
    // Publish to a user-visible location. On Android the file lives in
    // app-private storage, so hand it to the native MediaStore publisher; on
    // desktop it's already under the user's Downloads.
    if (fileOk && Platform.isAndroid) {
      unawaited(publishRecording(path, userInitiated: userInitiated));
    } else if (userInitiated && _host.mounted) {
      ScaffoldMessenger.of(_host.context).showSnackBar(
        SnackBar(
          content: Text(
            fileOk
                ? 'Recording saved: $path'
                : 'Recording failed — mpv wrote no file (see logs)',
          ),
        ),
      );
    }
  }

  Future<void> publishRecording(
    String path, {
    required bool userInitiated,
  }) async {
    var published = false;
    try {
      final fileName = path.split(Platform.pathSeparator).last;
      final uri = await AndroidNativeDownloader.saveLocalFile(
        path: path,
        fileName: fileName,
        mimeType: 'video/x-matroska',
      );
      published = uri != null;
    } catch (e) {
      debugPrint('VideoPlayer: publish recording failed: $e');
    }
    if (!userInitiated || !_host.mounted) return;
    // On failure, don't claim a save the user can't find: the file sits in
    // app-private storage, its registry entry survives (only a successful
    // publish clears it), and the next app launch re-attempts the publish.
    ScaffoldMessenger.of(_host.context).showSnackBar(
      SnackBar(
        content: Text(
          published
              ? 'Recording saved to Downloads/Debrify/Recordings'
              : "Recording couldn't be added to Downloads — "
                    'will retry next launch',
        ),
      ),
    );
  }

  /// One truth for "is this playback being recorded right now", shared by
  /// the dock's Record button and the styled zap banner's REC tag — the
  /// three mechanisms are libmpv stream-record, the Android recording
  /// engine, and the desktop capture process.
  bool get recordingActiveNow =>
      _host.isRecording ||
      _host.engineTaskId != null ||
      _host.desktopCaptureForCurrent() != null;
}
