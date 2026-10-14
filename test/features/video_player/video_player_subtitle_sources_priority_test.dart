import 'dart:async';
import 'dart:io';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/subtitle_sources_driver.dart';
import 'support/fake_player.dart';
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;
import 'video_player_subtitle_apply_boundaries_test.dart' show crossBoundary;

const priorityScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/priority.mp4',
  title: 'Priority original',
  contentImdbId: 'tt1100001',
  contentType: 'movie',
);

void main() {
  for (final outcome in ['success', 'failure']) {
    testWidgets(
      'subtitle priority waits for higher loading addon then $outcome',
      (t) async {
        final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
        await d.setup();
        await d.register('higher');
        await d.register('lower');
        await d.order();
        final response = Completer<http.Response>();
        d.f.network.handler = (r) => r.url.toString() == d.endpoint('higher')
            ? response.future
            : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
        try {
          await d.mount(screen: priorityScreen, publishTracks: false);
          await d.f.until(t, () => d.requests(d.endpoint('lower')) == 1);
          await d.f.advance(t, const Duration(seconds: 1));
          expect(d.player.state.track.subtitle.uri, isFalse);
          expect(d.requests(d.caption('lower')), 0);
          expect(d.requests(d.caption('higher')), 0);
          response.complete(
            outcome == 'success' ? d.slots('higher') : http.Response('{}', 404),
          );
          if (outcome == 'failure') {
            await d.f.until(
              t,
              () => d.logs.any((s) => s.contains('higher attempt 1/3 failed')),
            );
            await d.f.advance(t, const Duration(milliseconds: 500));
            await d.f.until(t, () => d.requests(d.endpoint('higher')) == 2);
            await d.f.advance(t, const Duration(milliseconds: 1500));
            await d.f.until(t, () => d.requests(d.endpoint('higher')) == 3);
          }
          await d.f.until(t, () => d.player.state.track.subtitle.uri);
          await d.f.actions.settle(t);
          final name = outcome == 'success' ? 'higher' : 'lower';
          expect(d.requests(d.caption(name)), 1);
          expect(
            d.requests(d.caption(name == 'higher' ? 'lower' : 'higher')),
            0,
          );
          expect(
            await t.runAsync(
              () => File(d.player.state.track.subtitle.id).readAsString(),
            ),
            contains(name),
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!response.isCompleted) {
            response.complete(http.Response('{}', 404));
          }
          await removeFixture(d);
        }
      },
    );
  }
  for (final event in ['manual', 'audio', 'profile', 'dispose']) {
    testWidgets(
      'subtitle held automatic download crossed by $event preserves original validity',
      (t) async {
        final d = SubtitleSourcesDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            (p.platform as FakeNativePlayer)
                    .properties['current-tracks/audio/lang'] =
                'fra';
          },
        );
        await d.setup();
        await d.register('held');
        await d.order(language: 'eng');
        if (event == 'audio') {
          await d.f.finish(
            t,
            SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
          );
          await d.f.finish(
            t,
            SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
          );
        }
        final response = Completer<http.Response>();
        Future<void>? audioSelection;
        d.f.network.handler = (r) => r.url.toString() == d.caption('held')
            ? response.future
            : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
        try {
          await d.mount(screen: priorityScreen, publishTracks: false);
          await d.f.until(t, () => d.requests(d.caption('held')) == 1);
          expect(d.player.state.track.subtitle.uri, isFalse);
          if (event == 'manual') {
            expect(await d.select('3'), isTrue);
          } else if (event == 'audio') {
            final panel = await d.menu();
            d.native.properties['current-tracks/audio/lang'] = 'eng';
            var done = false;
            audioSelection = d.observe(() => panel.onAudioSelected('1', 'no'));
            audioSelection!.then((_) => done = true);
            await d.f.until(t, () => d.player.state.track.subtitle.id == 'no');
            expect(done, isFalse);
          } else {
            await crossBoundary(d, event);
          }
          response.complete(d.f.network.replies[d.caption('held')]!);
          if (audioSelection != null) {
            await d.f.finish(t, audioSelection);
          }
          await d.f.actions.settle(t);
          await d.f.advance(t, const Duration(milliseconds: 200));
          if (event == 'profile') {
            expect(d.player.state.track.subtitle.uri, isTrue);
            expect(
              d.logs.any((v) => v.contains('external subtitle set')),
              isTrue,
            );
          } else {
            expect(d.player.state.track.subtitle.uri, isFalse);
            if (event == 'manual') {
              expect(d.player.state.track.subtitle.id, '3');
            }
          }
          expect(
            d.f.directory.listSync().whereType<File>().where(
              (f) => f.path.endsWith('.srt'),
            ),
            hasLength(1),
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!response.isCompleted) {
            response.complete(http.Response('{}', 404));
          }
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'subtitle service retry outlives disposed route without native apply',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('retry');
      await d.order();
      d.f.network.handler = (r) => r.url.toString() == d.endpoint('retry')
          ? http.Response('{}', 503)
          : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
      try {
        await d.mount(
          screen: priorityScreen,
          publishTracks: false,
          settleInitialization: false,
        );
        await d.f.until(t, () => d.requests(d.endpoint('retry')) >= 1);
        final before = d.player.calls.where((c) => c.$1 == 'subtitle').length;
        await crossBoundary(d, 'dispose');
        await d.f.advance(t, const Duration(seconds: 3));
        await d.f.actions.settle(t);
        expect(d.requests(d.endpoint('retry')), 3);
        expect(d.requests(d.caption('retry')), 0);
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle'),
          hasLength(before),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle priority storage change alone schedules no reselection',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('later');
      await d.order(language: 'eng', embeddedFirst: true);
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '2');
        expect(d.requests(d.caption('later')), 0);
        await d.order();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(d.player.state.track.subtitle.id, '2');
        expect(d.requests(d.caption('later')), 0);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  for (final action in ['native track', 'failed manual', 'manual success']) {
    testWidgets(
      'subtitle policy $action dispatch uses its retained refresh caller',
      (t) async {
        final d = SubtitleSourcesDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            final native = p.platform as FakeNativePlayer;
            var reads = 0;
            native.beforeOperation = (name, value) {
              if (name == 'getProperty' &&
                  value == 'current-tracks/audio/lang') {
                native.properties['current-tracks/audio/lang'] = ++reads == 1
                    ? 'eng'
                    : 'fra';
              }
            };
          },
        );
        await d.setup();
        await d.register('policy');
        await d.order(language: 'eng');
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
        );
        try {
          await d.mount(screen: priorityScreen, publishTracks: false);
          await d.f.until(t, () => d.player.state.track.subtitle.uri);
          await d.f.until(
            t,
            () => d.logs.any((s) => s.contains('external subtitle set')),
          );
          d.native.beforeOperation = null;
          d.native.calls.clear();
          if (action == 'native track') {
            d.native.properties['current-tracks/audio/lang'] = 'eng';
            final track = d.player.state.track.copyWith(
              audio: const mk.AudioTrack('1', 'English audio', 'eng'),
            );
            d.player.state = d.player.state.copyWith(track: track);
            d.player.emit('track', track);
            await d.f.until(t, () => d.player.state.track.subtitle.id == 'no');
            expect(
              d.native.calls.where(
                (c) =>
                    c.$1 == 'getProperty' &&
                    c.$2 == 'current-tracks/audio/lang',
              ),
              hasLength(1),
            );
            expect(
              d.logs.any((s) => s.contains('external subtitle cleared')),
              isTrue,
            );
            d.native.properties['current-tracks/audio/lang'] = 'fra';
            final returning = d.player.state.track.copyWith(
              audio: const mk.AudioTrack('2', 'French audio', 'fra'),
            );
            d.player.state = d.player.state.copyWith(track: returning);
            d.player.emit('track', returning);
            await d.f.until(t, () => d.player.state.track.subtitle.uri);
            await d.f.until(
              t,
              () =>
                  d.logs
                      .where((s) => s.contains('external subtitle set'))
                      .length ==
                  2,
            );
            expect(d.requests(d.caption('policy')), 1);
          } else if (action == 'manual success') {
            expect(await d.select('3'), isTrue);
            d.native.calls.clear();
            d.native.properties['current-tracks/audio/lang'] = 'eng';
            final track = d.player.state.track.copyWith(
              audio: const mk.AudioTrack('1', 'English audio', 'eng'),
            );
            d.player.state = d.player.state.copyWith(track: track);
            d.player.emit('track', track);
            await d.f.actions.settle(t);
            expect(d.player.state.track.subtitle.id, '3');
            expect(
              d.native.calls.where(
                (c) =>
                    c.$1 == 'getProperty' &&
                    c.$2 == 'current-tracks/audio/lang',
              ),
              isEmpty,
            );
          } else {
            d.native.properties['current-tracks/audio/lang'] = 'fra';
            d.player.failures['subtitle'] = StateError(
              'manual selection failed',
            );
            expect(await d.select('3'), isFalse);
            await d.f.actions.settle(t);
            await d.f.until(
              t,
              () => d.native.calls.any(
                (c) =>
                    c.$1 == 'getProperty' &&
                    c.$2 == 'current-tracks/audio/lang',
              ),
            );
            expect(
              d.native.calls.where(
                (c) =>
                    c.$1 == 'getProperty' &&
                    c.$2 == 'current-tracks/audio/lang',
              ),
              hasLength(1),
            );
            expect(d.player.state.track.subtitle.uri, isTrue);
            expect((await d.saved())?['subtitleTrackId'], isNull);
          }
          expect(d.requests(d.caption('policy')), 1);
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'subtitle final restoration policy refresh samples changed native audio before discovery',
    (t) async {
      final gate = Completer<void>();
      var reads = 0;
      var entered = false;
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          final native = p.platform as FakeNativePlayer;
          native.heldOperation = (name, value) =>
              name == 'getProperty' &&
              value == 'current-tracks/audio/lang' &&
              reads == 2 &&
              !gate.isCompleted;
          native.beforeOperation = (name, value) async {
            if (name == 'getProperty' && value == 'current-tracks/audio/lang') {
              reads++;
              if (reads == 3) {
                entered = true;
                await gate.future;
              }
              native.properties['current-tracks/audio/lang'] = reads == 2
                  ? 'fra'
                  : 'eng';
            }
          };
        },
      );
      await d.setup();
      await d.register('final-policy');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      try {
        await d.mount(
          screen: priorityScreen,
          publishTracks: false,
          settleInitialization: false,
        );
        await d.f.until(t, () => entered);
        expect(reads, 3);
        expect(d.requests(d.caption('final-policy')), 0);
        expect(d.logs.where((s) => s.contains('restore done')), isEmpty);
        gate.complete();
        await d.f.until(t, () => d.logs.any((s) => s.contains('restore done')));
        await d.f.until(t, () => d.requests(d.endpoint('final-policy')) == 1);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(d.requests(d.caption('final-policy')), 0);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle replacement defers policy reselection until stored restoration publishes readiness',
    (t) async {
      var creations = 0;
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          creations++;
          final native = p.platform as FakeNativePlayer;
          if (creations == 1) {
            var reads = 0;
            native.beforeOperation = (name, value) {
              if (name == 'getProperty' &&
                  value == 'current-tracks/audio/lang') {
                native.properties['current-tracks/audio/lang'] = ++reads == 1
                    ? 'eng'
                    : 'fra';
              }
            };
          } else {
            native.properties['current-tracks/audio/lang'] = 'eng';
          }
        },
      );
      await d.setup();
      await d.register('reselect');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
      await d.f.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.until(
          t,
          () => d.logs.any((s) => s.contains('external subtitle set')),
        );
        final restores = d.logs.where((s) => s.contains('restore done')).length;
        await crossBoundary(d, 'replacement');
        await d.f.until(
          t,
          () =>
              d.logs.where((s) => s.contains('restore done')).length > restores,
        );
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['no', 'no'],
        );
        expect(d.requests(d.caption('reselect')), 1);
        expect(d.errors, isEmpty);
      } finally {
        VpS2Hooks.install(null);
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle embedded priority clears its applied latch when preferred audio turns captions off',
    (t) async {
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          final native = p.platform as FakeNativePlayer;
          var reads = 0;
          native.beforeOperation = (name, value) {
            if (name == 'getProperty' && value == 'current-tracks/audio/lang') {
              native.properties['current-tracks/audio/lang'] = ++reads == 1
                  ? 'eng'
                  : 'fra';
            }
          };
        },
      );
      await d.setup();
      await d.register('embedded-latch');
      await d.order(language: 'spa', embeddedFirst: true);
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '3');
        d.native.beforeOperation = null;
        d.native.properties['current-tracks/audio/lang'] = 'eng';
        final preferred = d.player.state.track.copyWith(
          audio: const mk.AudioTrack('1', 'English audio', 'eng'),
        );
        d.player.state = d.player.state.copyWith(track: preferred);
        d.player.emit('track', preferred);
        await d.f.until(t, () => d.player.state.track.subtitle.id == 'no');
        await d.f.actions.settle(t);
        d.native.properties['current-tracks/audio/lang'] = 'fra';
        final foreign = d.player.state.track.copyWith(
          audio: const mk.AudioTrack('2', 'French audio', 'fra'),
        );
        d.player.state = d.player.state.copyWith(track: foreign);
        d.player.emit('track', foreign);
        await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
        expect(d.requests(d.caption('embedded-latch')), 0);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle stored auto samples foreign audio before selecting the embedded default',
    (t) async {
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          (p.platform as FakeNativePlayer)
                  .properties['current-tracks/audio/lang'] =
              'fra';
        },
      );
      await d.setup();
      await d.register('stored-policy');
      await d.order(language: 'spa', embeddedFirst: true);
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      await d.f.finish(
        t,
        TrackPreferencesStorage.saveVideoTrackPreferences(
          videoTitle: priorityScreen.title,
          audioTrackId: '2',
          subtitleTrackId: 'auto',
        ),
      );
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '3');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['3'],
        );
        expect(
          d.logs,
          contains(
            'SubAuto: restore done — embeddedSubtitleApplied=true → running addon auto-select',
          ),
        );
        expect(d.requests(d.caption('stored-policy')), 0);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle stored-auto replacement defers policy reselection until restoration publishes readiness',
    (t) async {
      var creations = 0;
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          creations++;
          final native = p.platform as FakeNativePlayer;
          if (creations == 1) {
            var reads = 0;
            native.beforeOperation = (name, value) {
              if (name == 'getProperty' &&
                  value == 'current-tracks/audio/lang') {
                native.properties['current-tracks/audio/lang'] = ++reads == 1
                    ? 'eng'
                    : 'fra';
              }
            };
          } else {
            native.properties['current-tracks/audio/lang'] = 'eng';
          }
        },
      );
      await d.setup();
      await d.register('reselect');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      await d.f.finish(
        t,
        TrackPreferencesStorage.saveVideoTrackPreferences(
          videoTitle: priorityScreen.title,
          audioTrackId: '2',
          subtitleTrackId: 'auto',
        ),
      );
      VpS2Hooks.install(VpS2Hooks(android: () => true, ios: () => false));
      await d.f.finish(
        t,
        PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.directSurface,
        ),
      );
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.until(
          t,
          () => d.logs.any((s) => s.contains('external subtitle set')),
        );
        final restores = d.logs.where((s) => s.contains('restore done')).length;
        await crossBoundary(d, 'replacement');
        await d.f.until(
          t,
          () =>
              d.logs.where((s) => s.contains('restore done')).length > restores,
        );
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['no', 'no'],
        );
        expect(d.requests(d.caption('reselect')), 1);
        expect(d.errors, isEmpty);
      } finally {
        VpS2Hooks.install(null);
        await removeFixture(d);
      }
    },
  );
  for (final failure in ['default', 'refresh']) {
    testWidgets(
      'subtitle $failure off request retains its diagnostic source on native rejection',
      (t) async {
        final d = SubtitleSourcesDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            (p.platform as FakeNativePlayer)
                    .properties['current-tracks/audio/lang'] =
                'eng';
            var requests = 0;
            p.beforeOperation = (name, value) {
              if (name == 'subtitle' &&
                  (value as mk.SubtitleTrack).id == 'no') {
                requests++;
                if (requests == (failure == 'default' ? 1 : 2)) {
                  throw StateError('synthetic off rejected');
                }
              }
            };
          },
        );
        await d.setup();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage('eng'),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
        );
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          final source = failure == 'default'
              ? 'audio-language-default-off'
              : 'audio-language-off';
          expect(
            d.logs.where(
              (s) => s.startsWith(
                '[SubtitleDiag] set FAILED source=$source requestedId=no error=Bad state: synthetic off rejected',
              ),
            ),
            hasLength(1),
          );
          expect(d.player.state.track.subtitle.id, 'no');
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'subtitle early off return and applied result precede a held final foreign-audio sample',
    (t) async {
      final gate = Completer<void>();
      var reads = 0;
      var entered = false;
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          final native = p.platform as FakeNativePlayer;
          native.heldOperation = (name, value) =>
              name == 'getProperty' &&
              value == 'current-tracks/audio/lang' &&
              reads == 2 &&
              !gate.isCompleted;
          native.beforeOperation = (name, value) async {
            if (name == 'getProperty' && value == 'current-tracks/audio/lang') {
              reads++;
              if (reads == 3) {
                entered = true;
                await gate.future;
              }
              native.properties['current-tracks/audio/lang'] = reads >= 3
                  ? 'fra'
                  : 'eng';
            }
          };
        },
      );
      await d.setup();
      await d.register('late-foreign');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      try {
        await d.mount(
          screen: priorityScreen,
          publishTracks: false,
          settleInitialization: false,
        );
        await d.f.until(t, () => entered);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.logs.where(
            (s) => s.startsWith('SubAuto: defaultSubtitleLanguage setting'),
          ),
          isEmpty,
        );
        expect(d.requests(d.caption('late-foreign')), 0);
        gate.complete();
        await d.f.until(
          t,
          () => d.logs.any((s) => s.contains('external subtitle set')),
        );
        expect(d.player.state.track.subtitle.uri, isTrue);
        expect(d.requests(d.caption('late-foreign')), 1);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        await removeFixture(d);
      }
    },
  );
  for (final failure in ['discovery', 'download', 'apply']) {
    testWidgets(
      'subtitle $failure failure falls through addon priority to embedded preference',
      (t) async {
        final d = SubtitleSourcesDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            if (failure == 'apply') {
              p.beforeOperation = (name, value) {
                if (name == 'subtitle' && (value as mk.SubtitleTrack).uri) {
                  throw StateError('synthetic addon refused');
                }
              };
            }
          },
        );
        await d.setup();
        await d.register('fallthrough');
        await d.order(language: 'eng');
        if (failure == 'discovery') {
          d.f.network.replies[d.endpoint('fallthrough')] = http.Response(
            '{}',
            503,
          );
        }
        if (failure == 'download') {
          d.f.network.replies[d.caption('fallthrough')] = http.Response(
            '{}',
            503,
          );
        }
        try {
          await d.mount(
            screen: priorityScreen,
            publishTracks: false,
            settleInitialization: false,
          );
          if (failure == 'discovery') {
            await d.f.until(
              t,
              () => d.logs.any(
                (s) => s.contains('fallthrough attempt 1/3 failed'),
              ),
            );
            await d.f.advance(t, const Duration(milliseconds: 500));
            await d.f.until(
              t,
              () => d.requests(d.endpoint('fallthrough')) == 2,
            );
            await d.f.advance(t, const Duration(milliseconds: 1500));
          }
          await d.f.until(t, () => d.player.state.track.subtitle.id == '2');
          await d.f.actions.settle(t);
          expect(d.player.state.track.subtitle.uri, isFalse);
          expect(
            d.player.calls.where(
              (c) => c.$1 == 'subtitle' && (c.$2 as mk.SubtitleTrack).id == '2',
            ),
            hasLength(1),
          );
          expect(
            d.requests(d.endpoint('fallthrough')),
            failure == 'discovery' ? 3 : 1,
          );
          expect(
            d.requests(d.caption('fallthrough')),
            failure == 'discovery' ? 0 : 1,
          );
          expect(
            d.logs,
            contains(
              'SubAuto: matched EMBEDDED track id=2 lang=eng title=English captions — applying',
            ),
          );
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'subtitle regular embedded priority result latches against a later foreign-audio refresh',
    (t) async {
      var reads = 0;
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          final native = p.platform as FakeNativePlayer;
          native.beforeOperation = (name, value) {
            if (name == 'getProperty' && value == 'current-tracks/audio/lang') {
              native.properties['current-tracks/audio/lang'] = ++reads == 1
                  ? 'eng'
                  : 'fra';
            }
          };
        },
      );
      await d.setup();
      await d.register('embedded-latch');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      d.f.network.replies[d.caption('embedded-latch')] = http.Response(
        '{}',
        503,
      );
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.until(t, () => d.player.state.track.subtitle.id == '2');
        await d.f.actions.settle(t);
        expect(
          d.player.calls.where(
            (c) => c.$1 == 'subtitle' && (c.$2 as mk.SubtitleTrack).id == '2',
          ),
          hasLength(2),
        );
        final track = d.player.state.track.copyWith(
          audio: const mk.AudioTrack('3', 'French', 'fra'),
        );
        d.player.state = d.player.state.copyWith(track: track);
        d.observe(() => d.player.emit('track', track));
        await d.f.actions.settle(t);
        expect(d.player.state.track.audio.id, '3');
        expect(d.player.state.track.subtitle.id, '2');
        expect(
          d.player.calls.where(
            (c) => c.$1 == 'subtitle' && (c.$2 as mk.SubtitleTrack).id == '2',
          ),
          hasLength(2),
        );
        expect(d.requests(d.caption('embedded-latch')), 1);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle same audio choice re-samples native language through its retained callback',
    (t) async {
      var reads = 0;
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          final native = p.platform as FakeNativePlayer;
          native.beforeOperation = (name, value) {
            if (name == 'getProperty' && value == 'current-tracks/audio/lang') {
              native.properties['current-tracks/audio/lang'] = ++reads == 1
                  ? 'eng'
                  : 'fra';
            }
          };
        },
      );
      await d.setup();
      await d.register('explicit-refresh');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.until(
          t,
          () => d.logs.any((s) => s.contains('external subtitle set')),
        );
        await d.f.actions.settle(t);
        expect(d.player.state.track.audio.id, '2');
        expect(d.player.state.track.subtitle.uri, isTrue);
        d.native.beforeOperation = null;
        d.native.properties['current-tracks/audio/lang'] = 'eng';
        d.player.calls.clear();
        final panel = await d.menu();
        await d.f.finish(
          t,
          d.observe(
            () => panel.onAudioSelected('2', 'stremio:explicit-refresh'),
          ),
        );
        expect(d.player.state.track.audio.id, '2');
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['no'],
        );
        expect(d.requests(d.caption('explicit-refresh')), 1);
        expect(
          (await d.saved(title: priorityScreen.title))?['subtitleTrackId'],
          'auto',
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
}
