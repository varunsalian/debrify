import 'dart:async';
import 'dart:io';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

abstract interface class VpIptvRecordingResourcesHost {
  IptvChannel? get currentIptvChannel;
  String? get currentStreamUrl;
  mk.Player get player;
  StreamSubscription<mk.PlayerLog>? get recordLogSub;
  set recordLogSub(StreamSubscription<mk.PlayerLog>? v);
  String? get iptvSourceId;
  List<Map<String, dynamic>>? get iptvSources;
}

class VpIptvRecordingResources {
  VpIptvRecordingResources(this._host);
  final VpIptvRecordingResourcesHost _host;

  /// The desktop capture, when it belongs to the CURRENTLY PLAYING channel —
  /// asked of the SERVICE, not this screen's own field, so a capture the
  /// desktop SCHEDULER started shows up on (and stops from) the Record button
  /// too when its channel is being watched.
  DesktopRecordingCapture? desktopCaptureForCurrent() {
    final channel = _host.currentIptvChannel;
    if (channel == null) return null;
    final playing = playingLiveUrl(channel);
    if (playing == null) return null;
    final service = DesktopRecordingService.instance;
    final direct = service.captureForUrl(playing);
    if (direct != null) return direct;
    final twin = LiveRecordingService.xtreamTsTwin(playing);
    return twin != null ? service.captureForUrl(twin) : null;
  }

  /// The URL actually PLAYING for [channel]. NOT `_currentStreamUrl` for
  /// plain channels — the zap path never updates that field, so after a zap
  /// it still holds the previous channel's URL, and matching on it would pin
  /// the Record button (and its Stop!) to the wrong capture. The channel's
  /// own URL is the identity for everything except Stremio, whose playing URL
  /// is the resolved candidate only `_currentStreamUrl` knows.
  String? playingLiveUrl(IptvChannel channel) {
    if (!channel.url.startsWith('stremio-tv://')) return channel.url;
    final resolved = _host.currentStreamUrl;
    if (resolved == null || resolved.startsWith('stremio-tv://')) return null;
    return resolved;
  }

  /// The URL the ENGINE should capture for the current live channel, or null
  /// when only the tee can record it. mpv's own `file-format` is ground truth
  /// for what's actually playing (extension-less URLs lie); the URL shape is
  /// the fallback when the probe is unavailable.
  Future<String?> engineRecordUrlForCurrent() async {
    final channel = _host.currentIptvChannel;
    if (channel == null || channel.isLive != true) return null;
    final playing = playingLiveUrl(channel);
    if (playing == null || playing.isEmpty) return null;
    // The engine speaks HTTP only. rtmp/rtsp/udp/... channels go to the tee —
    // mpv plays them, so mpv can record them. Checked BEFORE the probe: mpv
    // reports e.g. "flv" for RTMP, which would read as progressive below.
    if (!playing.startsWith('http://') && !playing.startsWith('https://')) {
      return null;
    }
    String format = '';
    final platform = _host.player.platform;
    if (platform is mk.NativePlayer) {
      try {
        format = await platform.getProperty('file-format');
      } catch (_) {}
    }
    final lower = format.toLowerCase();
    if (lower.contains('hls') || lower.contains('dash')) {
      // Segmented for sure — only an Xtream `.ts` twin can rescue it.
      return LiveRecordingService.xtreamTsTwin(playing);
    }
    if (lower.isNotEmpty) {
      // Probe says progressive: record exactly what's playing.
      return playing;
    }
    return LiveRecordingService.engineRecordableUrl(playing);
  }

  /// `<Channel>_<yyyyMMdd_HHmmss>.ts` — same shape as the tee's target path
  /// (which additionally uniquifies against its own directory; MediaStore
  /// uniquifies for the engine).
  String recordingFileName(String channelName) {
    final safeName = channelName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${base}_$stamp.ts';
  }

  Future<({String id, int revision})?> currentRecordingResource() async {
    final channel = _host.currentIptvChannel;
    final sourceId =
        channel?.attributes['source_playlist_id'] ??
        channel?.attributes['series_playlist_id'] ??
        _host.iptvSourceId;
    if (sourceId == null) return null;
    // Fresh read first: the launch payload's revision predates any sources
    // edit made while this player lives (PiP, background), and every edit
    // bumps every source's revision — a stale one would be refused at start.
    try {
      final playlists = await IptvPlaylistStorage.getIptvPlaylists(
        forSettings: false,
      );
      for (final playlist in playlists) {
        if (playlist.id != sourceId) continue;
        final id = playlist.connectionResourceId;
        final revision = playlist.connectionResourceRevision;
        if (id != null && id.isNotEmpty && revision != null) {
          return (id: id, revision: revision);
        }
      }
    } catch (_) {
      // Storage unavailable mid-session: fall through to the launch payload.
    }
    for (final source in _host.iptvSources ?? const <Map<String, dynamic>>[]) {
      if (source['id'] != sourceId) continue;
      final id = source['connectionResourceId']?.toString();
      final revision = (source['connectionResourceRevision'] as num?)?.toInt();
      if (id != null && id.isNotEmpty && revision != null) {
        return (id: id, revision: revision);
      }
    }
    return null;
  }

  /// Print mpv log lines that matter while a tee recording runs.
  void tapMpvLogsForRecording() {
    _host.recordLogSub?.cancel();
    _host.recordLogSub = _host.player.stream.log.listen((log) {
      final level = log.level.toLowerCase();
      if (level != 'error' && level != 'fatal') return;
      debugPrint('VideoPlayer: mpv[${log.level}] ${log.prefix}: ${log.text}');
    });
  }

  void untapMpvLogs() {
    _host.recordLogSub?.cancel();
    _host.recordLogSub = null;
  }

  /// A path no other recording is using. The second-resolution stamp alone
  /// collides when the same channel is stopped and restarted inside one
  /// second, and that collision is destructive: libmpv would truncate (or
  /// append to) the previous file, and on Android the still-running publisher
  /// deletes its source once copied — taking the NEW recording with it. An
  /// existing file therefore means "in use": step aside with a suffix.
  ///
  /// Default `.mkv` (the TEE): mpv's recorder picks the output muxer from the
  /// filename, and media_kit's decode-trimmed FFmpeg ships no `mpegts` muxer
  /// ("recorder: Output format not found" → recording silently disabled —
  /// found live on macOS). Matroska is the only sane target IF a muxer
  /// exists. Raw byte copiers (the desktop capture, the Android engine) pass
  /// `extension: 'ts'` — their bytes ARE a transport stream, no muxer
  /// involved.
  Future<String> recordingTargetPath(
    String channelName, {
    String extension = 'mkv',
  }) async {
    final safeName = channelName
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    var base = safeName.isEmpty ? 'recording' : safeName;
    if (base.length > 60) base = base.substring(0, 60);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';

    Directory dir;
    if (Platform.isAndroid) {
      dir =
          (await getExternalStorageDirectory()) ?? await AppStorage.documents();
    } else {
      dir = (await getDownloadsDirectory()) ?? await AppStorage.documents();
    }
    final sep = Platform.pathSeparator;
    final prefix = '${dir.path}${sep}Debrify${sep}Recordings$sep${base}_$stamp';

    var candidate = '$prefix.$extension';
    for (var n = 2; n < 100 && await File(candidate).exists(); n++) {
      candidate = '${prefix}_$n.$extension';
    }
    // Pathological (99 restarts in one second): fall back to microseconds,
    // which cannot collide with any of the names tried above.
    if (await File(candidate).exists()) {
      candidate = '${prefix}_${now.microsecondsSinceEpoch}.$extension';
    }
    return candidate;
  }
}
