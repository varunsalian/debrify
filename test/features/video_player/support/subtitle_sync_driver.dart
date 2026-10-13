import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_player.dart';
import 'player_actions.dart';
import 'video_player_environment.dart';

typedef SpeechSpan = ({int start, int end});

/// Deterministic data reaches the real SRT parser, audio tap and compute
/// aligner. No fake engine, synthetic notice, or private State access.
class SubtitleSyncDriver {
  SubtitleSyncDriver({
    bool native = true,
    this.fileTransport = false,
    void Function(FakePlayer)? configurePlayer,
  }) : fixture = VideoPlayerEnvironment(
         native: native,
         configurePlayer: (p) {
           if (native && !fileTransport) {
             final platform = p.platform! as FakeNativePlayer;
             platform.beforeOperation = (name, value) {
               if (name == 'command' &&
                   (value as List<String>).any(
                     (v) => v.contains('ametadata=mode=print:file='),
                   )) {
                 throw StateError(
                   'Fixture framework has no ametadata file filter',
                 );
               }
             };
           }
           configurePlayer?.call(p);
         },
       );
  final bool fileTransport;
  final VideoPlayerEnvironment fixture;
  final logs = <String>[];
  final errors = <Object>[];
  final timed = <(DateTime, Duration, Timer)>[];
  WidgetTester? timerTester;
  late DebugPrintCallback oldPrint;
  FakeNativePlayer get native => fixture.player.platform as FakeNativePlayer;
  static const screen = VideoPlayerScreen(
    videoUrl: 'https://player.test/subtitle-sync.mp4',
    title: 'Subtitle sync original',
  );

  Future<void> initialize(WidgetTester tester, {bool enabled = true}) async {
    await tester.runAsync(fixture.initialize);
    await fixture.finish(
      tester,
      SubtitleSettingsStorage.setSubtitleAutoSyncEnabled(enabled),
    );
    oldPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  }

  T observe<T>(T Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      handleUncaughtError: (self, parent, zone, error, stack) =>
          errors.add(error),
      createTimer: (self, parent, zone, duration, callback) {
        final timer = parent.createTimer(zone, duration, callback);
        timed.add((timerTester!.binding.clock.now(), duration, timer));
        return timer;
      },
    ),
  );

  Future<void> mount(
    WidgetTester tester, {
    VideoPlayerScreen screen = SubtitleSyncDriver.screen,
  }) {
    timerTester = tester;
    return observe(() => fixture.mount(tester, screen));
  }

  Future<void> timerEdge(
    WidgetTester tester,
    Duration duration, {
    int beforeMs = 0,
  }) async {
    expect(
      timed.any((v) => v.$2 == duration),
      isTrue,
      reason: 'Original must schedule the requested subtitle timer',
    );
    final start = timed.lastWhere((v) => v.$2 == duration).$1;
    final target = start.add(duration - Duration(milliseconds: beforeMs));
    final remaining = target.difference(tester.binding.clock.now());
    expect(remaining.isNegative, isFalse);
    await fixture.advance(tester, remaining);
  }

  AutoSyncPillModel? get pill => timerTester!
      .widget<ValueListenableBuilder<AutoSyncPillModel?>>(
        find.byWidgetPredicate(
          (w) => w is ValueListenableBuilder<AutoSyncPillModel?>,
        ),
      )
      .valueListenable
      .value;

  List<SpeechSpan> speech({int seed = 3, int durationMs = 180000}) {
    final random = math.Random(seed);
    final result = <SpeechSpan>[];
    var time = 500;
    while (time < durationMs - 3000) {
      final length = 600 + random.nextInt(1800);
      result.add((start: time, end: time + length));
      time += length + 400 + random.nextInt(2200);
    }
    return result;
  }

  String srt(List<SpeechSpan> spans, {int offsetMs = 2000}) {
    String stamp(int ms) {
      final d = Duration(milliseconds: ms.clamp(0, 10000000));
      String pad(int n, int width) => n.toString().padLeft(width, '0');
      return '${pad(d.inHours, 2)}:${pad(d.inMinutes % 60, 2)}:'
          '${pad(d.inSeconds % 60, 2)},${pad(d.inMilliseconds % 1000, 3)}';
    }

    return [
      for (final (i, span) in spans.indexed)
        '${i + 1}\n${stamp(span.start - offsetMs)} --> '
            '${stamp(span.end - offsetMs + 250)}\n'
            'Dialogue line with a plausible length here\n',
    ].join('\n');
  }

  Future<PlayerMenuPanel> select(
    WidgetTester tester, {
    String id = 'sync-fixture',
    int offsetMs = 2000,
    int seed = 3,
    int durationMs = 180000,
    String? caption,
  }) => observe(
    () => _select(
      tester,
      id: id,
      offsetMs: offsetMs,
      seed: seed,
      durationMs: durationMs,
      caption: caption,
    ),
  );

  Future<PlayerMenuPanel> _select(
    WidgetTester tester, {
    required String id,
    required int offsetMs,
    required int seed,
    required int durationMs,
    String? caption,
  }) async {
    final tv = find.byType(TvControls);
    late PlayerMenuPanel menu;
    if (tv.evaluate().isNotEmpty) {
      tester.widget<TvControls>(tv).onShowTracks();
      await fixture.advance(tester, const Duration(milliseconds: 300));
      menu = tester.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
    } else {
      menu = await openPlayerMenu(tester, fixture);
    }
    final subtitle = StremioSubtitle(
      id: id,
      url: 'https://player.test/$id.srt',
      lang: 'eng',
      source: 'Deterministic fixture',
    );
    fixture.network.replies[subtitle.url] = http.Response(
      srt(
        speech(seed: seed, durationMs: durationMs),
        offsetMs: offsetMs,
      ).replaceAll(
        'Dialogue line with a plausible length here',
        caption ?? 'Dialogue line with a plausible length here',
      ),
      200,
    );
    expect(
      await fixture.finish(tester, menu.onAddonSubtitleSelected(subtitle, '1')),
      isTrue,
    );
    menu.onClose();
    await fixture.advance(tester);
    return menu;
  }

  List<List<String>> get filterCommands => native.calls
      .where((c) => c.$1 == 'command')
      .map((c) => (c.$2 as List<String>))
      .where((c) => c.first == 'af')
      .toList();

  Future<File> installedFile(WidgetTester tester) async {
    await fixture.until(
      tester,
      () => filterCommands.any(
        (c) => c[1] == 'add' && c[2].contains('ametadata=mode=print:file='),
      ),
      reason: 'Production audio filter must install',
    );
    final filter = filterCommands.lastWhere((c) => c[1] == 'add')[2];
    final installs = filterCommands.where((c) => c[1] == 'add').length;
    await fixture.until(
      tester,
      () =>
          logs
              .where((l) => l.contains('tap installed (file transport)'))
              .length >=
          installs,
      reason: 'Filter entry alone does not prove activation completed',
    );
    return File(
      filter.split('ametadata=mode=print:file=').last.split(']').first,
    );
  }

  Future<void> feed(
    WidgetTester tester, {
    int seed = 3,
    int durationMs = 180000,
    int shiftMs = 0,
    bool append = false,
    int fromMs = 0,
  }) async {
    if (!fileTransport) {
      await fixture.until(
        tester,
        () => native.mapObservers.containsKey('af-metadata/debrify_autosync'),
      );
      await fixture.until(
        tester,
        () => logs.any((v) => v.contains('tap installed (property fallback)')),
      );
      final spans = speech(seed: seed, durationMs: durationMs);
      final random = math.Random(7);
      final observer = native.mapObservers['af-metadata/debrify_autosync']!;
      observe(() {
        for (var i = fromMs ~/ 32; i < durationMs ~/ 32; i++) {
          final time = i * 32;
          final spoken = spans.any(
            (s) => time - shiftMs >= s.start && time - shiftMs <= s.end,
          );
          var energy = 0.002 + random.nextDouble() * 0.001;
          if (spoken) {
            energy +=
                0.12 * ((i ~/ 6).isEven ? 1 : 0.25) +
                random.nextDouble() * 0.01;
          }
          observer({
            'lavfi.astats.Overall.RMS_level':
                '${20 * math.log(energy) / math.ln10}',
            'lavfi.astats.Overall.Number_of_samples': '1536',
            'lavfi.aspectralstats.1.centroid': '1700',
          });
        }
      });
      await fixture.advance(tester);
      return;
    }
    final file = await installedFile(tester);
    final spans = speech(seed: seed, durationMs: durationMs);
    final random = math.Random(7);
    final text = StringBuffer();
    for (var i = fromMs ~/ 32; i <= durationMs ~/ 32; i++) {
      final time = i * 32;
      final spoken = spans.any(
        (s) => time - shiftMs >= s.start && time - shiftMs <= s.end,
      );
      var energy = 0.002 + random.nextDouble() * 0.001;
      if (spoken) {
        energy +=
            0.12 * ((i ~/ 6).isEven ? 1 : 0.25) + random.nextDouble() * 0.01;
      }
      final rmsDb = 20 * math.log(energy) / math.ln10;
      text.writeln('frame:$i pts:0 pts_time:${time / 1000}');
      text.writeln('lavfi.astats.Overall.RMS_level=$rmsDb');
      text.writeln('lavfi.astats.Overall.Number_of_samples=1536');
      text.writeln('lavfi.aspectralstats.1.centroid=1700');
    }
    await tester.runAsync(
      () => file.writeAsString(
        text.toString(),
        mode: append ? FileMode.append : FileMode.write,
      ),
    );
    // A poll includes real file I/O, so pump the cadence and wait for its
    // completion before asking the real ladder to compute a result.

    await fixture.advance(tester, const Duration(milliseconds: 500));
    await fixture.advance(tester, const Duration(seconds: 8));
    await fixture.until(
      tester,
      () => logs.any((v) => v.contains('Subtitles synced')),
    );
  }

  AnimatedOpacity pillOpacity(WidgetTester tester) => tester.widget(
    find
        .ancestor(
          of: find.byType(AutoSyncPill),
          matching: find.byType(AnimatedOpacity),
        )
        .first,
  );

  AutoSyncPillPhase? phase(WidgetTester tester) {
    final found = find.byType(AutoSyncPill);
    return found.evaluate().isEmpty
        ? null
        : tester.widget<AutoSyncPill>(found).model.phase;
  }

  Future<void> close(WidgetTester tester) async {
    try {
      await fixture.close(tester);
    } finally {
      debugPrint = oldPrint;
    }
  }
}
