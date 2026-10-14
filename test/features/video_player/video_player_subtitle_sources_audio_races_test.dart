import 'dart:async';
import 'package:http/http.dart' as http;

import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/fake_player.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/subtitle_apply_driver.dart';
import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_apply_races_test.dart' show ApplyTurn;
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;
import 'video_player_subtitle_sources_priority_test.dart' show priorityScreen;
import 'support/identity_fixture.dart';
import 'package:debrify/screens/video_player_screen.dart';

void audioEvent(SubtitleApplyDriver d, String id, String tag) {
  d.native.properties['current-tracks/audio/lang'] = tag;
  final track = d.player.state.track.copyWith(
    audio: mk.AudioTrack(id, tag, tag),
  );
  d.player.state = d.player.state.copyWith(track: track);
  d.player.emit('track', track);
}

void main() {
  testWidgets(
    'subtitle latest audio revision wins a held earlier native language delivery',
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
      await d.register('audio-race');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      final held = CompletionDelivery(
        'refreshSubtitleAudioPolicy',
        (v) => v == 'eng',
      );
      try {
        await held.run(
          () => d.mount(screen: priorityScreen, publishTracks: false),
        );
        await d.f.until(
          t,
          () => d.logs.any((s) => s.contains('external subtitle set')),
        );
        final selected = d.player.state.track.subtitle.id;
        d.native.beforeOperation = null;
        d.player.calls.clear();
        held.run(() => d.observe(() => audioEvent(d, '1', 'eng')));
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(d.player.state.track.subtitle.id, selected);
        d.observe(() => audioEvent(d, '2', 'fra'));
        await d.f.actions.settle(t);
        expect(held.pending, hasLength(1));
        held.release();
        await d.f.actions.settle(t);
        expect(d.player.state.track.audio.id, '2');
        expect(d.player.state.track.subtitle.id, selected);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(d.requests(d.caption('audio-race')), 1);
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle stored policy choice wins an audio refresh admitted before its success turn',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          (p.platform as FakeNativePlayer)
                  .properties['current-tracks/audio/lang'] =
              'fra';
        },
      );
      await d.initialize();
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('spa'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      await d.f.finish(
        t,
        TrackPreferencesStorage.saveVideoTrackPreferences(
          videoTitle: applyScreen.title,
          audioTrackId: '2',
          subtitleTrackId: '3',
        ),
      );
      final success = ApplyTurn();
      final audio = CompletionDelivery(
        'refreshSubtitleAudioPolicy',
        (v) => v == 'eng',
      );
      try {
        await audio.run(
          () => success.run(
            () => d.mount(publishTracks: false, settleInitialization: false),
          ),
        );
        await d.f.until(t, () => success.pending.isNotEmpty);
        expect(d.player.state.track.subtitle.id, '3');
        expect(d.logs.where((s) => s.contains('restore done')), isEmpty);
        audio.run(() => d.observe(() => audioEvent(d, '1', 'eng')));
        await d.f.until(t, () => audio.pending.isNotEmpty);
        expect(d.player.state.track.subtitle.id, '3');
        success.release();
        await d.f.until(t, () => d.logs.any((s) => s.contains('restore done')));
        d.player.calls.clear();
        audio.release();
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '3');
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        success.release();
        audio.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle failed manual choice cannot resurrect an earlier audio revision',
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
      await d.register('failed-manual-race');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      final held = CompletionDelivery(
        'refreshSubtitleAudioPolicy',
        (v) => v == 'eng',
      );
      try {
        await held.run(
          () => d.mount(screen: priorityScreen, publishTracks: false),
        );
        await d.f.until(
          t,
          () => d.logs.any((s) => s.contains('external subtitle set')),
        );
        final selected = d.player.state.track.subtitle.id;
        d.native.beforeOperation = null;
        d.observe(() => audioEvent(d, '1', 'eng'));
        await d.f.until(t, () => held.pending.isNotEmpty);
        d.native.properties['current-tracks/audio/lang'] = 'fra';
        d.player.failures['subtitle'] = StateError(
          'synthetic failed manual choice',
        );
        expect(await d.select('3'), isFalse);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, selected);
        d.player.calls.clear();
        held.release();
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, selected);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle discovery cannot use the previous audio language while its next sample is pending',
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
      await d.register('pending-audio');
      await d.order(language: 'eng');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      final slots = Completer<http.Response>();
      final held = CompletionDelivery(
        'refreshSubtitleAudioPolicy',
        (v) => v == 'eng',
      );
      d.f.network.handler = (r) =>
          r.url.toString() == d.endpoint('pending-audio')
          ? slots.future
          : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
      try {
        await held.run(
          () => d.mount(screen: priorityScreen, publishTracks: false),
        );
        await d.f.until(t, () => d.requests(d.endpoint('pending-audio')) == 1);
        d.native.beforeOperation = null;
        d.observe(() => audioEvent(d, '1', 'eng'));
        await d.f.until(t, () => held.pending.isNotEmpty);
        slots.complete(d.slots('pending-audio'));
        await d.f.until(
          t,
          () => d.logs.any(
            (s) => s.contains('Fetched and cached 1 addon subtitles'),
          ),
        );
        await d.f.actions.settle(t);
        await d.f.advance(t, const Duration(milliseconds: 200));
        expect(held.pending, hasLength(1));
        expect(d.requests(d.caption('pending-audio')), 0);
        expect(d.player.state.track.subtitle.uri, isFalse);
        held.release();
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(d.requests(d.caption('pending-audio')), 0);
        expect(d.errors, isEmpty);
      } finally {
        if (!slots.isCompleted) {
          slots.complete(http.Response('{}', 404));
        }
        held.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle provisional default rejects an identified title changing only the content token',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('identity-default');
      await d.order(language: 'eng');
      await installIdentityCatalog(
        t,
        d.f,
        metas: [
          {
            'id': 'tt1100001',
            'imdb_id': 'tt1100001',
            'name': 'New subtitle identity',
            'type': 'movie',
          },
        ],
      );
      final search = d.f.network.handler!;
      d.f.network.handler = (r) => r.url.host == 'identity.test'
          ? search(r)
          : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
      var reads = 0;
      final held = CompletionDelivery(
        'applyDefaultSubtitleLanguage',
        (v) => v == 'eng' && ++reads == 2,
      );
      try {
        await held.run(
          () => d.mount(
            screen: const VideoPlayerScreen(
              videoUrl: 'https://player.test/unidentified.mp4',
              title: 'Unidentified playback',
            ),
            publishTracks: false,
          ),
        );
        await d.f.until(t, () => held.pending.isNotEmpty);
        expect(d.player.state.track.subtitle.uri, isFalse);
        final panel = await d.menu();
        final pending = d.observe(() => panel.onIdentifyTitle!());
        await d.f.until(
          t,
          () => find.text('New subtitle identity').evaluate().isNotEmpty,
        );
        await t.tap(find.text('New subtitle identity'));
        final identified = await d.f.finish(t, pending);
        expect(identified?.imdbId, 'tt1100001');
        await d.f.until(
          t,
          () => d.logs.any((s) => s.contains('external subtitle set')),
        );
        final matched = d.logs
            .where((s) => s.contains('matched EMBEDDED track'))
            .length;
        final selected = d.player.state.track.subtitle.id;
        d.player.calls.clear();
        expect(held.pending, hasLength(1));
        held.release();
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, selected);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(
          d.logs.where((s) => s.contains('matched EMBEDDED track')),
          hasLength(matched),
        );
        expect(d.errors, isEmpty);
      } finally {
        held.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle stale off success cannot repeat a newer provisional embedded selection',
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
      await d.register('provisional-off');
      await d.order(language: 'spa');
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      final turn = ApplyTurn()..armed = false;
      try {
        await turn.run(
          () => d.mount(
            screen: const VideoPlayerScreen(
              videoUrl: 'https://player.test/no-imdb.mp4',
              title: 'No IMDb yet',
            ),
            publishTracks: false,
          ),
        );
        await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
        await d.f.actions.settle(t);
        d.native.beforeOperation = null;
        turn.armed = true;
        d.observe(() => audioEvent(d, '1', 'eng'));
        await d.f.until(t, () => turn.pending.isNotEmpty);
        expect(d.player.state.track.subtitle.id, 'no');
        d.observe(() => audioEvent(d, '2', 'fra'));
        await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
        await d.f.actions.settle(t);
        final before = d.player.calls.where((c) => c.$1 == 'subtitle').length;
        expect(turn.pending, hasLength(1));
        turn.release();
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '3');
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle'),
          hasLength(before),
        );
        expect(d.requests(d.caption('provisional-off')), 0);
        expect(d.errors, isEmpty);
      } finally {
        turn.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle stale default-language read returns false before priority settings and readiness publication',
    (t) async {
      final d = SubtitleApplyDriver(
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
      await d.initialize();
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('spa'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      final language = CompletionDelivery(
        'applyDefaultSubtitleLanguage',
        (v) => v == 'spa',
      );
      var orders = 0;
      final order = CompletionDelivery('applyDefaultSubtitleLanguage', (v) {
        if (v is List<String>) {
          orders++;
        }
        return false;
      });
      try {
        await order.run(
          () => language.run(
            () => d.mount(publishTracks: false, settleInitialization: false),
          ),
        );
        await d.f.until(t, () => language.pending.isNotEmpty);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        d.native.beforeOperation = null;
        d.observe(() => audioEvent(d, '3', 'de'));
        await d.f.actions.settle(t);
        expect(language.pending, hasLength(1));
        language.release();
        await d.f.until(t, () => d.logs.any((s) => s.contains('restore done')));
        await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
        await d.f.actions.settle(t);
        expect(orders, 0);
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['3'],
        );
        expect(d.errors, isEmpty);
      } finally {
        language.release();
        order.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle stale default-source order returns false before matching and readiness publication',
    (t) async {
      final d = SubtitleApplyDriver(
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
      await d.initialize();
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setDefaultSubtitleLanguage('spa'),
      );
      await d.f.finish(
        t,
        SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(true),
      );
      final language = CompletionDelivery(
        'applyDefaultSubtitleLanguage',
        (v) => v is List<String>,
      );
      var orders = 0;
      final order = CompletionDelivery('applyDefaultSubtitleLanguage', (v) {
        if (v is List<String>) {
          orders++;
        }
        return false;
      });
      try {
        await order.run(
          () => language.run(
            () => d.mount(publishTracks: false, settleInitialization: false),
          ),
        );
        await d.f.until(t, () => language.pending.isNotEmpty);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        d.native.beforeOperation = null;
        d.observe(() => audioEvent(d, '3', 'de'));
        await d.f.actions.settle(t);
        expect(language.pending, hasLength(1));
        language.release();
        await d.f.until(t, () => d.logs.any((s) => s.contains('restore done')));
        await d.f.until(t, () => d.player.state.track.subtitle.id == '3');
        await d.f.actions.settle(t);
        expect(orders, 1);
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['3'],
        );
        expect(
          d.logs.where((v) => v.contains('matched EMBEDDED track id=3')),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        language.release();
        order.release();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle pending native sid default cannot overwrite a newer manual selection',
    (t) async {
      final gate = Completer<void>();
      var entered = false;
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          final native = p.platform as FakeNativePlayer;
          native.properties['sid'] = '2';
          native.heldOperation = (name, value) =>
              name == 'getProperty' && value == 'sid' && !gate.isCompleted;
          native.beforeOperation = (name, value) async {
            if (name == 'getProperty' && value == 'sid' && !entered) {
              entered = true;
              await gate.future;
            }
          };
        },
      );
      await d.initialize();
      try {
        await d.mount(publishTracks: false, settleInitialization: false);
        await d.f.until(t, () => entered);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(await d.select('3'), isTrue);
        expect(gate.isCompleted, isFalse);
        final applied = d.player.calls.where((c) => c.$1 == 'subtitle').length;
        gate.complete();
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '3');
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle'),
          hasLength(applied),
        );
        expect(
          d.logs,
          contains(
            'SubAuto: restore done — embeddedSubtitleApplied=false → running addon auto-select',
          ),
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle forced metadata pending during manual choice publishes the original unsuccessful restoration result',
    (t) async {
      final gate = Completer<void>();
      var entered = false;
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          final native = p.platform as FakeNativePlayer;
          native.properties.addAll({
            'track-list/count': '1',
            'track-list/0/type': 'sub',
            'track-list/0/forced': 'yes',
            'track-list/0/external': 'no',
            'track-list/0/lang': 'eng',
            'track-list/0/id': '2',
          });
          native.heldOperation = (name, value) =>
              name == 'getProperty' &&
              value == 'track-list/count' &&
              !gate.isCompleted;
          native.beforeOperation = (name, value) async {
            if (name == 'getProperty' &&
                value == 'track-list/count' &&
                !entered) {
              entered = true;
              await gate.future;
            }
          };
        },
      );
      await d.initialize();
      await d.f.finish(t, SubtitleSettingsStorage.setSubtitleForcedOnly(true));
      try {
        await d.mount(publishTracks: false, settleInitialization: false);
        await d.f.until(t, () => entered);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(await d.select('3'), isTrue);
        expect(gate.isCompleted, isFalse);
        final applied = d.player.calls.where((c) => c.$1 == 'subtitle').length;
        gate.complete();
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '3');
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle'),
          hasLength(applied),
        );
        expect(
          d.logs,
          contains(
            'SubAuto: restore done — embeddedSubtitleApplied=false → running addon auto-select',
          ),
        );
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await removeFixture(d);
      }
    },
  );
}
