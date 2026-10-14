import 'package:flutter/material.dart';
import 'package:debrify/models/stremio_subtitle.dart';
import 'package:http/http.dart' as http;
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_apply_driver.dart';

void main() {
  for (final native in [false, true]) {
    testWidgets(
      'subtitle apply ${native ? 'native' : 'non-native'} success persists the matching identity after its diagnostic turn',
      (t) async {
        final d = SubtitleApplyDriver(t, native: native);
        await d.initialize();
        try {
          await d.mount();
          final panel = await d.menu();
          if (native) d.native.calls.clear();
          expect(await d.select('2', panel: panel), isTrue);
          expect(d.player.state.track.subtitle.id, '2');
          expect((await d.saved())?['subtitleTrackId'], '2');
          expect((await d.saved())?['audioTrackId'], '1');
          if (native) {
            expect(d.native.properties['sub-visibility'], 'no');
            expect(
              d.native.calls
                  .where(
                    (v) =>
                        v.$1 == 'setProperty' &&
                        (v.$2 as (String, String)).$1 == 'sub-visibility',
                  )
                  .map((v) => (v.$2 as (String, String)).$2),
              ['no'],
            );
          }
          expect(
            d.timers.where(
              (v) =>
                  v.duration == const Duration(milliseconds: 50) &&
                  v.stack.contains('setSubtitleTrackWithDiagnostics'),
            ),
            isNotEmpty,
          );
          d.fail();
          await d.rollback('1');
          expect((await d.saved())?['subtitleTrackId'], '1');
          expect(
            find.text(
              'Couldn’t apply subtitles. Try another embedded or online track.',
            ),
            findsOneWidget,
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final previous in ['auto', '2']) {
    testWidgets(
      'subtitle failed apply falls back to no for previous $previous selection',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        try {
          await d.mount();
          d.player.state = d.player.state.copyWith(
            track: mk.Track(
              audio: d.player.state.track.audio,
              subtitle: previous == 'auto'
                  ? mk.SubtitleTrack.auto()
                  : applyTracks[1],
            ),
          );
          await d.f.advance(t);
          final panel = await d.menu();
          d.player.calls.clear();
          d.timers.clear();
          d.player.failures['subtitle'] = StateError('Rejected new captions');
          expect(await d.select('2', panel: panel), isFalse);
          expect(
            d.timers.where(
              (v) =>
                  v.duration == const Duration(milliseconds: 50) &&
                  v.stack.contains('setSubtitleTrackWithDiagnostics'),
            ),
            isEmpty,
          );
          expect(
            d.player.calls
                .where((v) => v.$1 == 'subtitle')
                .map((v) => (v.$2 as mk.SubtitleTrack).id),
            ['2', 'no'],
          );
          expect(d.player.state.track.subtitle.id, 'no');
          expect(await d.saved(), isNull);
          expect(
            d.logs.where((v) => v.contains('user notified')),
            hasLength(1),
          );
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'subtitle rollback second native failure preserves one original codec message',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final panel = await d.menu();
        var subtitleCalls = 0;
        d.player.beforeOperation = (name, value) {
          if (name == 'subtitle' && ++subtitleCalls <= 3) {
            throw StateError('native rejection $subtitleCalls');
          }
        };
        expect(await d.select('4', panel: panel), isFalse);
        expect(subtitleCalls, 3);
        expect(
          d.logs.where(
            (v) => v.startsWith(
              '[SubtitleDiag] rollback FAILED source=player-menu-embedded error=Bad state: native rejection 2',
            ),
          ),
          hasLength(1),
        );
        expect(d.logs.where((v) => v.contains('user notified')), hasLength(1));
        expect(
          find.text(
            'Couldn’t decode hdmv_pgs_subtitle subtitles. Try another embedded or online track.',
          ),
          findsOneWidget,
        );
        expect(await d.saved(), isNull);
        expect(d.errors, isEmpty);
      } finally {
        d.player.beforeOperation = null;
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle failure replaces the previous snackbar with a floating four-second message',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final panel = await d.menu();
        expect(await d.select('missing', panel: panel), isFalse);
        await d.f.advance(t, const Duration(milliseconds: 300));
        expect(
          find.text(
            'That subtitle track is no longer available. Try another track.',
          ),
          findsOneWidget,
        );
        d.player.failures['subtitle'] = StateError('second message');
        expect(await d.select('4', panel: panel), isFalse);
        await d.f.advance(t, const Duration(milliseconds: 300));
        final message = find.text(
          'Couldn’t decode hdmv_pgs_subtitle subtitles. Try another embedded or online track.',
        );
        expect(message, findsOneWidget);
        expect(
          find.text(
            'That subtitle track is no longer available. Try another track.',
          ),
          findsNothing,
        );
        final snackbar = t.widget<SnackBar>(
          find.ancestor(of: message, matching: find.byType(SnackBar)),
        );
        expect(snackbar.behavior, SnackBarBehavior.floating);
        expect(snackbar.duration, const Duration(seconds: 4));
        expect(
          d.logs.where(
            (v) => v.startsWith(
              '[SubtitleDiag] user notified source=player-menu-embedded reason=Bad state: second message',
            ),
          ),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final fallbackFails in [false, true]) {
    testWidgets(
      'subtitle previous addon identity and external path ${fallbackFails ? 'clear when native rollback fails' : 'restore together after an embedded failure'}',
      (t) async {
        final d = SubtitleApplyDriver(t);
        await d.initialize();
        try {
          await d.mount();
          var panel = await d.menu();
          expect(await d.addon('original-addon', panel: panel), isTrue);
          final previous = d.player.state.track.subtitle.id;
          expect(previous, isNot('1'));
          expect(
            (await d.saved())?['subtitleTrackId'],
            'stremio:original-addon',
          );
          expect(await d.select('2', panel: panel), isTrue);
          panel.onClose();
          await d.f.advance(t);
          panel = await d.menu();
          expect(panel.selectedSubtitleId, '2');
          if (fallbackFails) {
            d.player.failures['subtitle'] = StateError(
              'addon fallback rejected',
            );
          }
          d.fail();
          await d.rollback(fallbackFails ? 'no' : previous);
          expect(
            t
                .widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel))
                .selectedSubtitleId,
            fallbackFails ? 'no' : 'stremio:original-addon',
          );
          expect(
            (await d.saved())?['subtitleTrackId'],
            fallbackFails ? 'no' : 'stremio:original-addon',
          );
          panel.onClose();
          await d.f.advance(t);
          panel = await d.menu();
          expect(
            panel.selectedSubtitleId,
            fallbackFails ? 'no' : 'stremio:original-addon',
          );
          panel.onClose();
          panel.onSyncRequested!();
          await d.f.advance(t);
          if (fallbackFails) {
            expect(find.byType(SubtitleLinePickerOverlay), findsNothing);
          } else {
            expect(find.byType(SubtitleLinePickerOverlay), findsOneWidget);
            final overlay = t.widget<SubtitleLinePickerOverlay>(
              find.byType(SubtitleLinePickerOverlay),
            );
            expect(overlay.subtitleFilePath, previous);
            overlay.onDismiss();
            await d.f.advance(t);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'subtitle empty codec failure uses the generic diagnostic and restores native visibility',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        d.publish(
          tracks: [
            ...applyTracks,
            const mk.SubtitleTrack('6', 'Empty codec', 'eng', codec: ''),
          ],
        );
        await d.f.advance(t);
        final panel = await d.menu();
        d.player.failures['subtitle'] = StateError('empty codec failure');
        expect(await d.select('6', panel: panel), isFalse);
        expect(d.player.state.track.subtitle.id, '1');
        expect(d.native.properties['sub-visibility'], 'no');
        expect(
          find.text(
            'Couldn’t apply subtitles. Try another embedded or online track.',
          ),
          findsOneWidget,
        );
        expect(
          d.logs.where(
            (v) => v.startsWith(
              '[SubtitleDiag] set FAILED source=player-menu-embedded requestedId=6 error=Bad state: empty codec failure',
            ),
          ),
          hasLength(1),
        );
        expect(
          d.logs.where(
            (v) => v.startsWith(
              '[SubtitleDiag] user notified source=player-menu-embedded reason=Bad state: empty codec failure',
            ),
          ),
          hasLength(1),
        );
        expect(await d.saved(), isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'subtitle late text failure restores a previously selected bitmap with native visibility enabled',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final panel = await d.menu();
        expect(await d.select('4', panel: panel), isTrue);
        expect(d.native.properties['sub-visibility'], 'yes');
        d.native.calls.clear();
        expect(await d.select('2', panel: panel), isTrue);
        expect(d.native.properties['sub-visibility'], 'no');
        d.fail();
        await d.rollback('4');
        expect(d.native.properties['sub-visibility'], 'yes');
        expect(
          d.native.calls
              .where(
                (v) =>
                    v.$1 == 'setProperty' &&
                    (v.$2 as (String, String)).$1 == 'sub-visibility',
              )
              .map((v) => (v.$2 as (String, String)).$2),
          ['no', 'yes'],
        );
        expect((await d.saved())?['subtitleTrackId'], '4');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle failed rollback visibility retries no-track visibility before applying the no track',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final panel = await d.menu();
        d.native.calls.clear();
        d.player.calls.clear();
        var rejected = false;
        d.native.beforeOperation = (name, value) {
          if (!rejected &&
              name == 'setProperty' &&
              value == ('sub-visibility', 'no')) {
            rejected = true;
            throw StateError('rollback visibility rejected');
          }
        };
        d.player.failures['subtitle'] = StateError('bitmap apply rejected');
        expect(await d.select('4', panel: panel), isFalse);
        expect(
          d.player.calls
              .where((v) => v.$1 == 'subtitle')
              .map((v) => (v.$2 as mk.SubtitleTrack).id),
          ['4', 'no'],
        );
        expect(
          d.native.calls
              .where(
                (v) =>
                    v.$1 == 'setProperty' &&
                    (v.$2 as (String, String)).$1 == 'sub-visibility',
              )
              .map((v) => (v.$2 as (String, String)).$2),
          ['yes', 'no', 'no'],
        );
        expect(d.native.properties['sub-visibility'], 'no');
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.logs.where(
            (v) =>
                v ==
                '[SubtitleDiag] rollback FAILED source=player-menu-embedded error=Bad state: rollback visibility rejected',
          ),
          hasLength(1),
        );
        expect(
          find.text(
            'Couldn’t decode hdmv_pgs_subtitle subtitles. Try another embedded or online track.',
          ),
          findsOneWidget,
        );
        expect(d.errors, isEmpty);
      } finally {
        d.native.beforeOperation = null;
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle addon download failure uses the load-failure message caller without native apply or persistence',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final panel = await d.menu();
        const sub = StremioSubtitle(
          id: 'unavailable-addon',
          url: 'https://player.test/unavailable.srt',
          lang: 'eng',
          source: 'Fixture',
        );
        d.f.network.replies[sub.url] = http.Response('unavailable', 500);
        d.player.calls.clear();
        expect(
          await d.f.finish(
            t,
            d.observe(() => panel.onAddonSubtitleSelected(sub, '1')),
          ),
          isFalse,
        );
        expect(
          find.text(
            'Couldn’t load subtitles. Check your connection or try another track.',
          ),
          findsOneWidget,
        );
        expect(d.player.calls.where((v) => v.$1 == 'subtitle'), isEmpty);
        expect(await d.saved(), isNull);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'subtitle addon unexpected diagnostic sink failure reaches its outer failure-message caller',
    (t) async {
      final d = SubtitleApplyDriver(t);
      await d.initialize();
      final capture = debugPrint;
      var rejected = false;
      try {
        await d.mount();
        final panel = await d.menu();
        final recorder = debugPrint;
        debugPrint = (String? message, {int? wrapWidth}) {
          recorder(message, wrapWidth: wrapWidth);
          if (!rejected &&
              (message?.startsWith('[SubtitleDiag] set FAILED') ?? false)) {
            rejected = true;
            throw StateError('diagnostic sink rejected');
          }
        };
        d.player.failures['subtitle'] = StateError('native addon rejected');
        expect(await d.addon('unexpected-addon', panel: panel), isFalse);
        expect(rejected, isTrue);
        expect(
          find.text(
            'Couldn’t apply subtitles. Try another embedded or online track.',
          ),
          findsOneWidget,
        );
        expect(
          d.logs.where(
            (v) =>
                v ==
                'PlayerMenu: subtitle apply failed - Bad state: diagnostic sink rejected',
          ),
          hasLength(1),
        );
        expect(d.logs.where((v) => v.contains('user notified')), isEmpty);
        expect(d.player.state.track.subtitle.id, '1');
        expect(await d.saved(), isNull);
        expect(d.errors, isEmpty);
      } finally {
        debugPrint = capture;
        await d.close();
      }
    },
  );
}
