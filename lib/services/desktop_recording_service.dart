import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'live_recording_service.dart' show RecordingLibraryEntry;

/// How a desktop capture ended.
enum DesktopRecordingEnd {
  /// The user stopped it — the normal, happy ending.
  stopped,

  /// The stream stayed dead through the reconnect budget; whatever was
  /// captured up to the drop is on disk.
  streamEnded,

  /// Nothing usable was captured (couldn't connect, couldn't write, or the
  /// server handed us an HLS playlist instead of media bytes).
  failed,

  /// The 6h safety cap fired; the file up to the cap is on disk.
  durationCap,
}

/// One live capture: a plain HTTP byte copy of a progressive stream into a
/// local file. This is the Android engine's core loop transplanted to Dart
/// for desktop, where it is the ONLY recorder that works at all — mpv's
/// `stream-record` is dead on media_kit's stock libs ("recorder: Output
/// format not found": the bundled FFmpeg ships no muxers), while this needs
/// none: the bytes on the wire ARE the .ts file.
///
/// Same live-capture semantics as the engine: no Range/resume (live streams
/// don't rewind — a reconnect appends and TS tolerates the discontinuity),
/// EOF is a drop like any other, only [stop], the duration cap, or a stream
/// that stays dead through the reconnect budget end it.
class DesktopRecordingCapture {
  DesktopRecordingCapture._({
    required this.url,
    required this.path,
    required this.channelName,
    required Map<String, String> headers,
    this.onFinished,
  }) : _headers = headers;

  final String url;
  final String path;
  final String channelName;
  final Map<String, String> _headers;

  /// Called exactly once when the capture ends, however it ends. May fire on
  /// any async gap — listeners must check `mounted`.
  void Function(DesktopRecordingEnd end, int bytes)? onFinished;

  int _bytes = 0;
  int get bytes => _bytes;

  final DateTime startedAt = DateTime.now();

  bool _stopRequested = false;
  bool _done = false;
  bool get isActive => !_done;

  HttpClient? _client;
  final Completer<int> _completion = Completer<int>();

  static const _maxDuration = Duration(hours: 6);
  static const _maxDeadReconnects = 3;
  static const _stallTimeout = Duration(seconds: 60);
  static const _reconnectBackoff = Duration(seconds: 2);

  /// Ask the capture to end and force a blocked read out now. Resolves with
  /// the byte count once the file is flushed and closed.
  Future<int> stop() {
    _stopRequested = true;
    try {
      _client?.close(force: true);
    } catch (_) {}
    return _completion.future;
  }

  Future<void> _run() async {
    IOSink? sink;
    var end = DesktopRecordingEnd.failed;
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      sink = file.openWrite();

      var deadConnects = 0;
      var capReached = false;

      capture:
      while (!_stopRequested && !capReached) {
        HttpClient? client;
        var gotBytesThisAttempt = false;
        try {
          client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
          _client = client;
          final request = await client.getUrl(Uri.parse(url));
          _headers.forEach((k, v) => request.headers.set(k, v));
          if (!_headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
            // Providers routinely block default library UAs — look like the
            // player (mirrors the Android engine and the mpv fix before it).
            request.headers.set(
              'User-Agent',
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            );
          }
          final response = await request.close();
          if (response.statusCode != 200) {
            throw HttpException('HTTP ${response.statusCode} for live stream');
          }
          // A silent stream is a dead stream: no bytes for the stall window
          // surfaces as a TimeoutException and rolls into a reconnect.
          await for (final chunk in response.timeout(_stallTimeout)) {
            if (_stopRequested) break capture;
            if (chunk.isEmpty) continue;
            // First bytes of the whole capture: an HLS playlist wearing a
            // progressive URL would loop-append manifest text forever.
            if (_bytes == 0 &&
                chunk.length >= 7 &&
                String.fromCharCodes(chunk.take(7)) == '#EXTM3U') {
              end = DesktopRecordingEnd.failed;
              break capture;
            }
            sink.add(chunk);
            _bytes += chunk.length;
            gotBytesThisAttempt = true;
            if (DateTime.now().difference(startedAt) > _maxDuration) {
              capReached = true;
              break;
            }
          }
          // Clean EOF from a live server = a drop; fall through to reconnect.
        } catch (_) {
          if (_stopRequested) break capture;
          // Connect/read failure: reconnect accounting below.
        } finally {
          try {
            client?.close(force: true);
          } catch (_) {}
          if (identical(_client, client)) _client = null;
        }
        if (_stopRequested || capReached) break;

        // Only CONSECUTIVE dead attempts count against the budget.
        if (gotBytesThisAttempt) {
          deadConnects = 0;
        } else {
          deadConnects++;
          if (deadConnects >= _maxDeadReconnects) {
            end = DesktopRecordingEnd.streamEnded;
            break;
          }
        }
        final resumeAt = DateTime.now().add(_reconnectBackoff);
        while (DateTime.now().isBefore(resumeAt) && !_stopRequested) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      if (_stopRequested) {
        end = DesktopRecordingEnd.stopped;
      } else if (capReached) {
        end = DesktopRecordingEnd.durationCap;
      }
    } catch (e) {
      debugPrint('DesktopRecording: capture crashed: $e');
      end = DesktopRecordingEnd.failed;
    } finally {
      try {
        await sink?.flush();
      } catch (_) {}
      try {
        await sink?.close();
      } catch (_) {}
    }

    // A capture that saved nothing is a failure whatever the path here — and
    // its empty file is junk, not a recording.
    if (_bytes == 0) {
      end = DesktopRecordingEnd.failed;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    _done = true;
    debugPrint(
      'DesktopRecording: ended ($end) — $_bytes bytes at $path',
    );
    // In the capture itself, NOT an onFinished wrapper: callers may null
    // onFinished (the player does at dispose), and the UI revision must bump
    // for every ending regardless.
    DesktopRecordingService.instance.revision.value++;
    if (!_completion.isCompleted) _completion.complete(_bytes);
    try {
      onFinished?.call(end, _bytes);
    } catch (_) {}
  }
}

/// Desktop recording: one capture at a time (matching the in-player surface —
/// with no notifications on desktop, the Record button is the only stop
/// control, so parallel invisible captures would be unstoppable).
class DesktopRecordingService {
  DesktopRecordingService._();
  static final DesktopRecordingService instance = DesktopRecordingService._();

  /// Bumped when a capture starts or ends — UI (the IPTV stage's Record↔Stop
  /// button) observes this instead of only sampling on its own rebuilds, so
  /// a SCHEDULED capture starting while focus parks on the channel flips the
  /// button too.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  DesktopRecordingCapture? _active;

  /// The running capture, or null.
  DesktopRecordingCapture? get active {
    final capture = _active;
    if (capture == null || !capture.isActive) return null;
    return capture;
  }

  bool get isSupported =>
      !kIsWeb &&
      (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Begin capturing [url] to [path]. Returns null when another capture is
  /// already running.
  DesktopRecordingCapture? start({
    required String url,
    required String path,
    required String channelName,
    required Map<String, String> headers,
    void Function(DesktopRecordingEnd end, int bytes)? onFinished,
  }) {
    if (active != null) return null;
    final capture = DesktopRecordingCapture._(
      url: url,
      path: path,
      channelName: channelName,
      headers: headers,
      onFinished: onFinished,
    );
    _active = capture;
    revision.value++;
    unawaited(capture._run());
    return capture;
  }

  /// Stop the running capture, if any; resolves once its file is closed.
  Future<void> stopAll() async {
    final capture = active;
    if (capture != null) await capture.stop();
  }

  /// Where desktop recordings live: `<Downloads>/Debrify/Recordings`. One
  /// truth shared by the capture path builder and the library listing. Not
  /// created here — captures create it on first write.
  static Future<Directory> recordingsDir() async {
    final base =
        (await getDownloadsDirectory()) ??
        await getApplicationDocumentsDirectory();
    final sep = Platform.pathSeparator;
    return Directory('${base.path}${sep}Debrify${sep}Recordings');
  }

  static const _libraryExtensions = {'ts', 'mts', 'm2ts', 'mkv', 'mp4'};

  /// Finished recordings on disk (the folder IS the desktop library — there
  /// is no index to go stale). The active capture's still-growing file is
  /// excluded; it belongs to the "recording now" surface.
  static Future<List<RecordingLibraryEntry>> listLibrary() async {
    if (!instance.isSupported) return const [];
    final dir = await recordingsDir();
    if (!await dir.exists()) return const [];
    final activePath = instance.active?.path;
    final out = <RecordingLibraryEntry>[];
    try {
      await for (final item in dir.list(followLinks: false)) {
        if (item is! File || item.path == activePath) continue;
        final name = item.path.split(Platform.pathSeparator).last;
        final dot = name.lastIndexOf('.');
        final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
        if (!_libraryExtensions.contains(ext)) continue;
        final FileStat stat;
        try {
          stat = await item.stat();
        } catch (_) {
          continue;
        }
        if (stat.size <= 0) continue;
        out.add(
          RecordingLibraryEntry(
            taskId: null,
            uri: item.path,
            name: name,
            channelName: null,
            bytes: stat.size,
            recordedAtMs: stat.modified.millisecondsSinceEpoch,
            durationMs: null,
          ),
        );
      }
    } catch (_) {
      // Unreadable folder — an empty library beats a crash loop.
    }
    return out;
  }

  /// Delete a finished desktop recording. Refuses the active capture's file.
  static Future<bool> deleteRecordingFile(String path) async {
    if (instance.active?.path == path) return false;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
