import 'dart:math' as math;
import 'package:debrify/screens/video_player/services/subtitle_aligner.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/player_actions.dart';

import 'support/subtitle_sync_driver.dart';

void main() {
  for (final verdict in [false, true]) {
    testWidgets(
      'subtitle off then new selection cannot inherit an old ${verdict ? 'result' : 'announcement'} hide',
      (t) async {
        final d = SubtitleSyncDriver();
        await d.initialize(t);
        try {
          await d.mount(t);
          final original = await d.select(t);
          await d.feed(t, durationMs: verdict ? 180000 : 1000);
          if (verdict) {
            await d.fixture.advance(t, const Duration(seconds: 8));
            await d.fixture.until(
              t,
              () => d.pill?.phase == AutoSyncPillPhase.synced,
            );
          }
          final duration = verdict
              ? const Duration(milliseconds: 2400)
              : const Duration(seconds: 5);
          final old = d.timed.lastWhere((v) => v.$2 == duration);
          expect(
            await d.fixture.finish(t, original.onSubtitlesOff('1')),
            isTrue,
          );
          original.onSubtitleTrackChanged!();
          await d.fixture.advance(t);
          expect(d.pill, isNull);
          await d.select(t, id: 'after-off-${verdict ? 'result' : 'announce'}');
          await d.feed(t, durationMs: 1000);
          expect(d.pill?.phase, AutoSyncPillPhase.announce);
          final remaining = old.$1
              .add(old.$2)
              .difference(t.binding.clock.now());
          expect(remaining.isNegative, isFalse);
          await d.fixture.advance(t, remaining);
          expect(d.pill?.phase, AutoSyncPillPhase.announce);
          expect(d.errors, isEmpty);
        } finally {
          await d.close(t);
        }
      },
    );
  }

  testWidgets(
    'subtitle style timing feedback invalidates a held real alignment before its offset can win',
    (t) async {
      final d = SubtitleSyncDriver();
      final held = CompletionDelivery(
        '_runAlignment',
        (v) => v is SubtitleAlignResult,
      );
      await d.initialize(t);
      try {
        await d.mount(t);
        final menu = await held.run(() => d.select(t));
        await d.feed(t);
        await d.fixture.advance(t, const Duration(seconds: 8));
        await d.fixture.until(t, () => held.pending.isNotEmpty);
        expect(d.pill?.phase, AutoSyncPillPhase.checking);
        await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.setSyncOffsetMs(900),
        );
        final settings = await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.loadAll(),
        );
        menu.onSubtitleStyleChanged!(settings);
        await d.fixture.advance(t);
        expect(d.pill, isNull);
        expect(d.native.properties['sub-delay'], '0.900');
        expect(held.pending, hasLength(1));
        held.release();
        await d.fixture.advance(t);
        expect(d.native.properties['sub-delay'], '0.900');
        expect(
          await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.getSyncOffsetMs(),
          ),
          900,
        );
        expect(d.pill, isNull);
        expect(d.logs.where((v) => v.contains('Subtitles synced')), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close(t);
      }
    },
  );
  testWidgets(
    'subtitle fresh listening cancels the preceding announcement deadline',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        await d.select(t);
        await d.feed(t, durationMs: 1000);
        final old = d.timed.lastWhere(
          (v) => v.$2 == const Duration(seconds: 5),
        );
        await d.fixture.advance(t, const Duration(seconds: 1));
        await d.select(t, id: 'fresh-listening');
        await d.feed(t, durationMs: 1000);
        final fresh = d.timed.lastWhere(
          (v) => v.$2 == const Duration(seconds: 5),
        );
        expect(fresh.$1.isAfter(old.$1), isTrue);
        final remaining = old.$1.add(old.$2).difference(t.binding.clock.now());
        expect(remaining.isNegative, isFalse);
        await d.fixture.advance(t, remaining);
        expect(d.pill?.phase, AutoSyncPillPhase.announce);
        await d.timerEdge(t, const Duration(seconds: 5));
        expect(d.pill, isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );

  testWidgets('subtitle fresh audio listening cancels a failed verdict hold', (
    t,
  ) async {
    final d = SubtitleSyncDriver();
    await d.initialize(t);
    try {
      await d.mount(t);
      await d.select(t, seed: 99);
      await d.feed(t);
      for (var i = 0; i < 4; i++) {
        await d.fixture.advance(t, const Duration(seconds: 8));
        await d.fixture.until(
          t,
          () => d.pill?.phase != AutoSyncPillPhase.checking,
        );
      }
      await d.fixture.until(t, () => d.pill?.phase == AutoSyncPillPhase.failed);
      final old = d.timed.lastWhere(
        (v) => v.$2 == const Duration(milliseconds: 2400),
      );
      await d.observe(
        () => d.fixture.player.setAudioTrack(
          const mk.AudioTrack('2', 'French', 'fra'),
        ),
      );
      await d.fixture.until(
        t,
        () => d.pill?.phase == AutoSyncPillPhase.announce,
      );
      final remaining = old.$1.add(old.$2).difference(t.binding.clock.now());
      expect(remaining.isNegative, isFalse);
      await d.fixture.advance(t, remaining);
      expect(d.pill?.phase, AutoSyncPillPhase.announce);
      expect(d.errors, isEmpty);
    } finally {
      await d.close(t);
    }
  });
  testWidgets(
    'subtitle auto verdict rebuilds an already open sync overlay with the computed offset',
    (t) async {
      final d = SubtitleSyncDriver();
      final held = CompletionDelivery(
        '_runAlignment',
        (v) => v is SubtitleAlignResult,
      );
      await d.initialize(t);
      try {
        await d.mount(t);
        await held.run(() => d.select(t, caption: 'Short caption.'));
        await d.feed(t);
        await d.fixture.advance(t, const Duration(seconds: 8));
        await d.fixture.until(t, () => held.pending.isNotEmpty);
        final menu = await openPlayerMenu(t, d.fixture);
        menu.onClose();
        menu.onSyncRequested!();
        await d.fixture.advance(t);
        final overlay = t.widget<SubtitleLinePickerOverlay>(
          find.byType(SubtitleLinePickerOverlay),
        );
        expect(overlay.currentOffsetMs, 0);
        held.release();
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.synced,
        );
        final applied = await d.fixture.finish(
          t,
          SubtitleSettingsService.instance.getSyncOffsetMs(),
        );
        expect(applied, greaterThan(1000));
        expect(
          t
              .widget<SubtitleLinePickerOverlay>(
                find.byType(SubtitleLinePickerOverlay),
              )
              .currentOffsetMs,
          applied,
        );
        expect(
          d.native.properties['sub-delay'],
          (applied / 1000).toStringAsFixed(3),
        );
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close(t);
      }
    },
  );
  testWidgets(
    'subtitle cumulative real verification clamps the native and session offset at the positive bound',
    (t) async {
      final d = SubtitleSyncDriver(
        speechWindows: [
          (start: 0, end: 180000),
          for (var pass = 1; pass <= 41; pass++)
            (start: 600000 + pass * 511000, end: 675000 + pass * 511000),
        ],
      );
      final held = CompletionDelivery(
        '_verify',
        (v) => v is SubtitleAlignResult,
      );
      const length = 30000000;
      final spans = d.speech(durationMs: length);
      await d.initialize(t);
      try {
        await d.mount(t);
        await held.run(() => d.select(t, durationMs: length));
        await d.feed(t);
        await d.fixture.advance(t, const Duration(seconds: 8));
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.synced,
        );
        await d.timerEdge(t, const Duration(milliseconds: 2400));
        var resyncs = 0;
        for (var pass = 1; pass <= 41; pass++) {
          final position = 600000 + pass * 600000;
          final shift = pass * 89000;
          d.fixture.player.state = d.fixture.player.state.copyWith(
            position: Duration(milliseconds: position),
          );
          d.fixture.player.emit('position', d.fixture.player.state.position);
          await d.fixture.advance(t);
          final observer =
              d.native.mapObservers['af-metadata/debrify_autosync']!;
          var cursor = 0;
          final random = math.Random(7);
          // Feed real metadata, anchored by the production position observer.
          // Disjoint windows keep old offsets out of the verification snapshot.
          d.observe(() {
            for (var i = position ~/ 32; i < (position + 180000) ~/ 32; i++) {
              final sourceTime = i * 32 - shift;
              while (cursor < spans.length && spans[cursor].end < sourceTime) {
                cursor++;
              }
              final spoken =
                  cursor < spans.length &&
                  sourceTime >= spans[cursor].start &&
                  sourceTime <= spans[cursor].end;
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
          await d.fixture.advance(t);
          // Verification selects segments through the current playback clock.
          // Advance it to the end of the fed audio before taking the snapshot.
          d.fixture.player.state = d.fixture.player.state.copyWith(
            position: Duration(milliseconds: position + 180000),
          );
          d.fixture.player.emit('position', d.fixture.player.state.position);
          await d.fixture.advance(t);
          for (var attempt = 0; attempt < 3; attempt++) {
            held.armed = true;
            final timersBefore = d.timed
                .where((v) => v.$2 == const Duration(seconds: 120))
                .length;
            await d.timerEdge(
              t,
              Duration(seconds: pass == 1 && attempt == 0 ? 90 : 120),
            );
            await d.fixture.until(
              t,
              () => held.pending.isNotEmpty,
              reason:
                  'pass $pass attempt $attempt: ${d.logs.reversed.take(6).join(" | ")}',
            );
            expect(
              held.values.last,
              attempt < 2
                  ? isA<SubtitleAlignNoMatch>()
                  : isA<SubtitleAlignSynced>(),
              reason:
                  'pass $pass attempt $attempt ${held.values.last is SubtitleAlignNoMatch ? (held.values.last as SubtitleAlignNoMatch).bestOffsetMs : null}/${held.values.last is SubtitleAlignNoMatch ? (held.values.last as SubtitleAlignNoMatch).bestZ : null}/${held.values.last is SubtitleAlignNoMatch ? (held.values.last as SubtitleAlignNoMatch).bestPsr : null}',
            );
            held.release();
            if (attempt < 2) {
              await d.fixture.until(
                t,
                () =>
                    d.timed
                        .where((v) => v.$2 == const Duration(seconds: 120))
                        .length >
                    timersBefore,
              );
            } else {
              await d.fixture.until(
                t,
                () =>
                    d.logs
                        .where((v) => v.contains('Subtitles re-synced'))
                        .length >
                    resyncs,
              );
            }
          }
          resyncs++;
          expect(
            d.logs.where((v) => v.contains('Subtitles re-synced')),
            hasLength(resyncs),
          );
          final expected = (2000 + shift).clamp(
            SubtitleSettingsService.syncOffsetMinMs,
            SubtitleSettingsService.syncOffsetMaxMs,
          );
          final settings = await d.fixture.finish(
            t,
            SubtitleSettingsService.instance.loadAll(),
          );
          if (pass < 41) {
            expect(settings.syncOffsetMs, closeTo(expected, 500));
            expect(
              double.parse(d.native.properties['sub-delay']!) * 1000,
              closeTo(expected, 500),
            );
          } else {
            expect(
              settings.syncOffsetMs,
              SubtitleSettingsService.syncOffsetMaxMs,
            );
            expect(d.native.properties['sub-delay'], '3600.000');
            final menu = await openPlayerMenu(t, d.fixture);
            menu.onClose();
            menu.onSyncRequested!();
            await d.fixture.advance(t);
            expect(
              t
                  .widget<SubtitleLinePickerOverlay>(
                    find.byType(SubtitleLinePickerOverlay),
                  )
                  .currentOffsetMs,
              SubtitleSettingsService.syncOffsetMaxMs,
            );
          }
          expect(d.pill, isNull);
        }
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await d.close(t);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'subtitle verification corrects later drift silently after the result pill fades',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        await d.select(t, durationMs: 900000);
        await d.feed(t);
        await d.fixture.advance(t, const Duration(seconds: 8));
        await d.fixture.until(
          t,
          () => d.pill?.phase == AutoSyncPillPhase.synced,
        );
        await d.timerEdge(t, const Duration(milliseconds: 2400));
        expect(d.pill, isNull);
        d.fixture.player.state = d.fixture.player.state.copyWith(
          position: const Duration(seconds: 600),
        );
        d.fixture.player.emit('position', d.fixture.player.state.position);
        await d.fixture.advance(t);
        final original = d.native.properties['sub-delay'];
        await d.feed(t, fromMs: 600000, durationMs: 780000, shiftMs: 3000);
        await d.timerEdge(t, const Duration(seconds: 90));
        await d.fixture.until(
          t,
          () => d.native.properties['sub-delay'] != original,
        );
        expect(
          double.parse(d.native.properties['sub-delay']!),
          closeTo(4.85, .15),
        );
        expect(
          d.logs.where((v) => v.contains('Subtitles re-synced')),
          hasLength(1),
        );
        expect(d.pill, isNull);
        expect(d.pillOpacity(t).opacity, 0);
        expect(d.phase(t), AutoSyncPillPhase.synced);
        expect(d.errors, isEmpty);
      } finally {
        await d.close(t);
      }
    },
  );
  testWidgets('real subtitle engine announces then aligns fixture metadata', (
    tester,
  ) async {
    final d = SubtitleSyncDriver();
    await d.initialize(tester);
    try {
      await d.mount(tester);
      await d.select(tester);

      await d.fixture.until(
        tester,
        () => d.phase(tester) == AutoSyncPillPhase.announce,
      );
      expect(d.pillOpacity(tester).opacity, 1);
      expect(d.logs, contains('SubtitleAutoSync: Trying to sync subtitles…'));
      await d.timerEdge(tester, const Duration(seconds: 5), beforeMs: 1);
      expect(d.pill, isNotNull);
      await d.fixture.advance(tester, const Duration(milliseconds: 1));
      expect(d.pill, isNull);
      expect(d.pillOpacity(tester).opacity, 0);
      expect(d.pillOpacity(tester).duration, const Duration(milliseconds: 350));
      expect(d.phase(tester), AutoSyncPillPhase.announce);
      await d.feed(tester);
      await d.fixture.advance(tester, const Duration(seconds: 8));
      await d.fixture.until(
        tester,
        () => d.native.properties['sub-delay'] != null,
        reason: 'Real alignment must update native subtitle timing',
      );
      expect(d.native.properties['sub-delay'], '1.869');
      expect(d.phase(tester), AutoSyncPillPhase.synced);
      expect(d.logs, contains('SubtitleAutoSync: Checking subtitle timing…'));
      expect(d.logs, contains('SubtitleAutoSync: Subtitles synced +1.9s'));
      expect(d.logs.join('\n'), contains('Subtitles synced'));
      expect(d.filterCommands.where((c) => c[1] == 'add'), hasLength(2));
      expect(
        await d.fixture.finish(
          tester,
          SubtitleSettingsService.instance.getSyncOffsetMs(),
        ),
        1869,
      );
      await d.timerEdge(
        tester,
        const Duration(milliseconds: 2400),
        beforeMs: 1,
      );
      expect(d.pill?.phase, AutoSyncPillPhase.synced);
      await d.fixture.advance(tester, const Duration(milliseconds: 1));
      expect(d.pill, isNull);
      expect(d.pillOpacity(tester).opacity, 0);
      expect(d.phase(tester), AutoSyncPillPhase.synced);
      await d.fixture.advance(tester, const Duration(milliseconds: 349));
      final fade = tester.widget<FadeTransition>(
        find.descendant(
          of: find.ancestor(
            of: find.byType(AutoSyncPill),
            matching: find.byType(AnimatedOpacity),
          ),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(fade.opacity.value, greaterThan(0));
      await d.fixture.advance(tester, const Duration(milliseconds: 1));
      expect(fade.opacity.value, 0);
      expect(d.errors, isEmpty);
    } finally {
      await d.close(tester);
    }
  });

  testWidgets('subtitle checking stays visible until real alignment finishes', (
    t,
  ) async {
    final d = SubtitleSyncDriver();
    final held = CompletionDelivery(
      '_runAlignment',
      (v) => v is SubtitleAlignResult,
    );
    await d.initialize(t);
    try {
      await d.mount(t);
      await held.run(() => d.select(t));
      await d.feed(t);
      await d.fixture.advance(t, const Duration(seconds: 8));
      await d.fixture.until(t, () => held.pending.isNotEmpty);
      expect(d.pill?.phase, AutoSyncPillPhase.checking);
      expect(d.pillOpacity(t).opacity, 1);
      expect(d.native.properties['sub-delay'], isNull);
      await d.fixture.advance(t, const Duration(seconds: 5));
      expect(d.pill?.phase, AutoSyncPillPhase.checking);
      held.release();
      await d.fixture.until(t, () => d.pill?.phase == AutoSyncPillPhase.synced);
      expect(d.native.properties['sub-delay'], '1.869');
    } finally {
      held.release();
      await d.close(t);
    }
  });

  testWidgets('subtitle intermediate no verdict quietly keeps listening', (
    t,
  ) async {
    final d = SubtitleSyncDriver();
    await d.initialize(t);
    try {
      await d.mount(t);
      await d.select(t, seed: 99);
      await d.feed(t, durationMs: 21000);
      await d.fixture.advance(t, const Duration(seconds: 8));
      await d.fixture.until(
        t,
        () => d.logs.any((line) => line.contains('No verdict yet')),
      );
      expect(d.pill, isNull);
      expect(d.pillOpacity(t).opacity, 0);
      expect(d.phase(t), AutoSyncPillPhase.checking);
      expect(d.native.properties['sub-delay'], isNull);
      expect(
        d.logs.where((line) => line.contains('Trying to sync')),
        hasLength(1),
      );
    } finally {
      await d.close(t);
    }
  });

  testWidgets(
    'subtitle exhausted unrelated metadata produces a failed result',
    (t) async {
      final d = SubtitleSyncDriver();
      await d.initialize(t);
      try {
        await d.mount(t);
        await d.select(t, seed: 99);
        await d.feed(t);
        for (var i = 0; i < 4; i++) {
          final count = d.logs
              .where((line) => line.contains('Checking subtitle'))
              .length;
          await d.fixture.advance(t, const Duration(seconds: 8));
          await d.fixture.until(
            t,
            () =>
                d.logs
                    .where((line) => line.contains('Checking subtitle'))
                    .length >
                count,
          );
          await d.fixture.until(
            t,
            () => d.pill?.phase != AutoSyncPillPhase.checking,
          );
        }
        expect(d.pill?.phase, AutoSyncPillPhase.failed);
        expect(d.pillOpacity(t).opacity, 1);
        expect(find.text('LEFT UNCHANGED'), findsOneWidget);
        expect(d.native.properties['sub-delay'], isNull);
        await d.timerEdge(t, const Duration(milliseconds: 2400));
        expect(d.pill, isNull);
        expect(d.pillOpacity(t).opacity, 0);
      } finally {
        await d.close(t);
      }
    },
  );
}
