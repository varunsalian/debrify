import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:debrify/screens/video_player/services/media_kit_audio_feature_tap.dart';
import 'package:debrify/screens/video_player/services/media_kit_subtitle_auto_sync.dart';
import 'package:debrify/screens/video_player/services/subtitle_aligner.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Span = ({int start, int end});

/// Same feature-level synthesis as the aligner tests: "speech" = strong,
/// syllabically modulated band energy; the rest is a low noise floor.
List<_Span> _speechPattern(int fromMs, int toMs, {int seed = 3}) {
  final random = math.Random(seed);
  final output = <_Span>[];
  var time = fromMs + 500;
  while (time < toMs - 1000) {
    final length = 600 + random.nextInt(1800);
    output.add((start: time, end: time + length));
    time += length + 400 + random.nextInt(2200);
  }
  return output;
}

AudioFeatureSegment _segment(
  int anchorMs,
  int durationMs,
  List<_Span> speech, {
  int seed = 7,
}) {
  const frameMs = 32.0;
  final count = (durationMs / frameMs).floor();
  final band = List<double>.filled(count, 0);
  final broad = List<double>.filled(count, 0);
  final random = math.Random(seed);
  var index = 0;
  for (var i = 0; i < count; i++) {
    final time = anchorMs + (i * frameMs).floor();
    while (index < speech.length && speech[index].end < time) {
      index++;
    }
    final inSpeech =
        index < speech.length &&
        time >= speech[index].start &&
        time <= speech[index].end;
    var bandValue = 0.002 + random.nextDouble() * 0.001;
    var broadValue = 0.004 + random.nextDouble() * 0.002;
    if (inSpeech) {
      final syllable = (i ~/ 6).isEven ? 1.0 : 0.25;
      bandValue += 0.12 * syllable + random.nextDouble() * 0.01;
      broadValue += 0.13 * syllable;
    }
    band[i] = bandValue;
    broad[i] = broadValue;
  }
  return AudioFeatureSegment(
    anchorMs: anchorMs,
    sampleRate: 48000,
    frameSamples: 1536,
    band: band,
    broadband: broad,
  );
}

String _srtTime(int ms) {
  final clamped = math.max(0, ms);
  final h = clamped ~/ 3600000;
  final m = (clamped % 3600000) ~/ 60000;
  final s = (clamped % 60000) ~/ 1000;
  final f = clamped % 1000;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)},${f.toString().padLeft(3, '0')}';
}

/// Cues for [speech], authored EARLY by [earlyMs] (so the right offset is
/// +[earlyMs]) and optionally time-scaled first (framerate drift).
Future<String> _writeSrt(
  Directory directory,
  String name,
  List<_Span> speech, {
  int earlyMs = 0,
  double scale = 1,
}) async {
  final buffer = StringBuffer();
  var index = 1;
  for (final span in speech) {
    final start = (span.start * scale).floor() - earlyMs;
    final end = (span.end * scale).floor() - earlyMs + 250;
    if (start < 0) continue;
    buffer
      ..writeln(index++)
      ..writeln('${_srtTime(start)} --> ${_srtTime(end)}')
      ..writeln('Dialogue line with a plausible length here')
      ..writeln();
  }
  final file = File('${directory.path}/$name.srt');
  await file.writeAsString(buffer.toString());
  return file.path;
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

class _Harness {
  _Harness(this.tap, {this.positionMs = 90000});

  final _FakeTap tap;
  int positionMs;
  int storedOffset = 0;
  double storedScale = 1;
  final List<int> appliedOffsets = <int>[];
  final List<double> appliedScales = <double>[];
  final List<SubtitleAutoSyncNotice> notices = <SubtitleAutoSyncNotice>[];
  late final MediaKitSubtitleAutoSync controller =
      MediaKitSubtitleAutoSync.forTesting(
        tap: tap,
        enabled: true,
        currentPositionMs: () => positionMs,
        isPlaying: () => true,
        currentOffsetMs: () => storedOffset,
        applyOffsetMs: (ms) async {
          storedOffset = ms;
          appliedOffsets.add(ms);
        },
        applyScale: (scale) async {
          storedScale = scale;
          appliedScales.add(scale);
        },
        onNotice: notices.add,
      );

  Iterable<SubtitleAutoSyncNoticeKind> get kinds =>
      notices.map((n) => n.kind);
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('autosync-');
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'subtitle deactivation cannot strand an in-flight filter install',
    () async {
      final subtitle = File('${directory.path}/track.srt');
      await subtitle.writeAsString(
        '1\n00:00:01,000 --> 00:00:03,000\nA spoken line.\n',
      );

      final tap = _BlockingTap();
      final notices = <SubtitleAutoSyncNotice>[];
      final controller = MediaKitSubtitleAutoSync.forTesting(
        tap: tap,
        enabled: true,
        currentPositionMs: () => 0,
        isPlaying: () => true,
        currentOffsetMs: () => 0,
        applyOffsetMs: (_) async {},
        onNotice: notices.add,
      );
      addTearDown(controller.dispose);

      final activation = controller.activateSubtitle(subtitle.path);
      await tap.installStarted.future;
      final deactivation = controller.deactivateSubtitle();
      tap.allowInstall.complete();
      await Future.wait(<Future<void>>[activation, deactivation]);

      expect(tap.installed, isFalse);
      expect(tap.installCalls, 1);
      expect(tap.uninstallCalls, greaterThanOrEqualTo(1));
      expect(notices, isEmpty);
    },
  );

  test('a subtitle switch reuses the audio already heard and syncs at once',
      () async {
    final speech = _speechPattern(0, 90000);
    final tap = _FakeTap(<AudioFeatureSegment>[_segment(0, 90000, speech)]);
    final h = _Harness(tap);
    addTearDown(h.controller.dispose);
    final first = await _writeSrt(directory, 'a', speech, earlyMs: 2000);
    final second = await _writeSrt(directory, 'b', speech, earlyMs: 3000);

    await h.controller.activateSubtitle(first);
    await _waitFor(() => h.appliedOffsets.isNotEmpty);
    expect(h.appliedOffsets.single, closeTo(2000, 300));
    expect(tap.installCalls, 1);
    expect(h.kinds, contains(SubtitleAutoSyncNoticeKind.synced));

    // The host resets the live offset on a subtitle change; the audio
    // history must NOT reset with it.
    h.storedOffset = 0;
    final before = DateTime.now();
    await h.controller.activateSubtitle(second);
    await _waitFor(() => h.appliedOffsets.length == 2);
    expect(h.appliedOffsets.last, closeTo(3000, 300));
    expect(DateTime.now().difference(before).inSeconds, lessThan(10));
    expect(tap.installCalls, 1, reason: 'tap reused, not reinstalled');
    expect(tap.uninstallCalls, 0);
    expect(tap.resetCalls, 1, reason: 'only the first install resets');
  });

  test('deactivation keeps the tap listening; dispose uninstalls it',
      () async {
    final speech = _speechPattern(0, 60000);
    final tap = _FakeTap(<AudioFeatureSegment>[_segment(0, 60000, speech)]);
    final h = _Harness(tap);
    final path = await _writeSrt(directory, 'a', speech, earlyMs: 1500);
    await h.controller.activateSubtitle(path);
    await _waitFor(() => h.appliedOffsets.isNotEmpty);

    await h.controller.deactivateSubtitle();
    expect(tap.installed, isTrue);
    expect(tap.uninstallCalls, 0);

    await h.controller.contentChanged();
    expect(tap.resetCalls, 2, reason: 'content change discards history');

    await h.controller.dispose();
    expect(tap.installed, isFalse);
  });

  test('a restored sync is adopted and verified, never re-searched',
      () async {
    final speech = _speechPattern(0, 120000);
    final tap = _FakeTap(<AudioFeatureSegment>[_segment(0, 120000, speech)]);
    final h = _Harness(tap, positionMs: 120000)..storedOffset = 2000;
    addTearDown(h.controller.dispose);
    final path = await _writeSrt(directory, 'a', speech, earlyMs: 2000);

    await h.controller.activateSubtitle(
      path,
      restored: (offsetMs: 2000, scale: 1),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(h.appliedOffsets, isEmpty);
    expect(h.kinds, isNot(contains(SubtitleAutoSyncNoticeKind.listening)));
    expect(h.controller.applied, (offsetMs: 2000, scale: 1.0));

    // A verify pass over a correct restore confirms silently.
    await h.controller.verifyNow();
    expect(h.appliedOffsets, isEmpty);
    expect(h.controller.applied, (offsetMs: 2000, scale: 1.0));
  });

  test('framerate drift is applied as a scale plus an offset', () async {
    final speech = _speechPattern(0, 3 * 60000);
    final tap = _FakeTap(<AudioFeatureSegment>[
      _segment(0, 3 * 60000, speech),
    ]);
    final h = _Harness(tap, positionMs: 3 * 60000);
    addTearDown(h.controller.dispose);
    // Cues authored on 25 fps timing for 23.976 fps audio.
    final path = await _writeSrt(
      directory,
      'drift',
      speech,
      earlyMs: -1500,
      scale: 23.976 / 25,
    );

    await h.controller.activateSubtitle(path);
    await _waitFor(() => h.appliedOffsets.isNotEmpty);
    expect(h.appliedScales.last, closeTo(25 / 23.976, 0.002));
    expect(h.appliedOffsets.last, closeTo(-1564, 500));
    expect(h.controller.applied?.scale, closeTo(25 / 23.976, 0.002));
    expect(h.kinds, contains(SubtitleAutoSyncNoticeKind.synced));
  });

  test('a sync the film keeps refusing to confirm is withdrawn', () async {
    final speech = _speechPattern(0, 6 * 60000);
    final tap = _FakeTap(<AudioFeatureSegment>[
      _segment(0, 6 * 60000, speech),
    ]);
    final h = _Harness(tap, positionMs: 6 * 60000);
    addTearDown(h.controller.dispose);
    final path = await _writeSrt(directory, 'a', speech, earlyMs: 2000);
    await h.controller.activateSubtitle(path);
    await _waitFor(() => h.appliedOffsets.isNotEmpty);
    expect(h.appliedOffsets.single, closeTo(2000, 300));

    // The audio under the playhead stops agreeing with the cues (wrong
    // subtitle for this cut, say). Three verify passes — residual, residual,
    // escalated full-width — all find nothing.
    tap.segments = <AudioFeatureSegment>[
      _segment(0, 6 * 60000, _speechPattern(0, 6 * 60000, seed: 43), seed: 9),
    ];
    await h.controller.verifyNow();
    await h.controller.verifyNow();
    expect(h.controller.applied, isNotNull);
    await h.controller.verifyNow();
    expect(h.appliedOffsets.last, 0, reason: 'sync withdrawn');
    expect(h.storedScale, 1);
    // Withdrawal re-arms the search; unrelated audio still yields no verdict.
    await _waitFor(
      () => h.kinds.contains(SubtitleAutoSyncNoticeKind.failed) ||
          h.controller.applied != null,
    );
    expect(h.controller.applied, isNull);
  });
}

class _FakeTap implements MediaKitAudioFeatureTap {
  _FakeTap(this.segments);

  List<AudioFeatureSegment> segments;
  int installCalls = 0;
  int uninstallCalls = 0;
  int resetCalls = 0;
  bool _installed = false;

  @override
  double get anchoredDurationMs =>
      segments.fold<double>(0, (sum, s) => sum + s.durationMs);

  @override
  bool get installed => _installed;

  @override
  bool get reliable => true;

  @override
  Future<bool> install() async {
    installCalls++;
    _installed = true;
    return true;
  }

  @override
  Future<void> uninstall() async {
    uninstallCalls++;
    _installed = false;
  }

  @override
  void reset({int? anchorMs}) {
    resetCalls++;
  }

  @override
  Future<void> resetForAudioTrack({required int anchorMs}) async {
    resetCalls++;
  }

  @override
  bool observePosition(int positionMs) => false;

  @override
  List<AudioFeatureSegment> snapshot() =>
      List<AudioFeatureSegment>.unmodifiable(segments);

  @override
  void ingestMetadata(Map<String, String> metadata) {}

  @override
  void ingestPrintOutput(String text) {}

  @override
  Future<void> dispose() async {
    await uninstall();
  }
}

class _BlockingTap implements MediaKitAudioFeatureTap {
  final Completer<void> installStarted = Completer<void>();
  final Completer<void> allowInstall = Completer<void>();

  int installCalls = 0;
  int uninstallCalls = 0;
  bool _installed = false;

  @override
  double get anchoredDurationMs => 0;

  @override
  bool get installed => _installed;

  @override
  bool get reliable => true;

  @override
  Future<bool> install() async {
    installCalls++;
    installStarted.complete();
    await allowInstall.future;
    _installed = true;
    return true;
  }

  @override
  Future<void> uninstall() async {
    uninstallCalls++;
    _installed = false;
  }

  @override
  void reset({int? anchorMs}) {}

  @override
  Future<void> resetForAudioTrack({required int anchorMs}) async {}

  @override
  bool observePosition(int positionMs) => false;

  @override
  List<AudioFeatureSegment> snapshot() => const <AudioFeatureSegment>[];

  @override
  void ingestMetadata(Map<String, String> metadata) {}

  @override
  void ingestPrintOutput(String text) {}

  @override
  Future<void> dispose() async {
    await uninstall();
  }
}
