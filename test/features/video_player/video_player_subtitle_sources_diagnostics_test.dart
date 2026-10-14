import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/subtitle_apply_driver.dart';
import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_sources_priority_test.dart' show priorityScreen;
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer, languageTracks;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;

void main() {
  for (final mode in [
    'no preference',
    'language',
    'off',
    'forced missing',
    'forced match',
  ]) {
    testWidgets(
      'subtitle $mode native rejection keeps the original diagnostic source',
      (t) async {
        var rejected = false;
        final d = SubtitleApplyDriver(
          t,
          configurePlayer: (p) {
            seedLanguagePlayer(p);
            final native = p.platform as FakeNativePlayer;
            native.properties.addAll({
              'track-list/count': '1',
              'track-list/0/type': 'sub',
              'track-list/0/forced': mode == 'forced match' ? 'yes' : 'no',
              'track-list/0/external': 'no',
              'track-list/0/lang': 'eng',
              'track-list/0/id': '2',
            });
            p.beforeOperation = (name, value) {
              if (name == 'subtitle' && !rejected) {
                rejected = true;
                throw StateError('synthetic selection refused');
              }
            };
          },
        );
        await d.initialize();
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setDefaultSubtitleLanguage(
            mode == 'no preference'
                ? null
                : mode == 'off'
                ? 'off'
                : 'eng',
          ),
        );
        await d.f.finish(
          t,
          SubtitleSettingsStorage.setSubtitleForcedOnly(
            mode.startsWith('forced'),
          ),
        );
        try {
          await d.mount(publishTracks: false);
          await d.f.actions.settle(t);
          final source = switch (mode) {
            'no preference' => 'no-preference-embedded',
            'language' => 'default-language-embedded',
            'off' => 'default-language-off',
            'forced missing' => 'forced-only-off',
            _ => 'forced-only-embedded',
          };
          final id = mode == 'off' || mode == 'forced missing' ? 'no' : '2';
          expect(rejected, isTrue);
          expect(
            d.logs.where(
              (s) => s.startsWith(
                '[SubtitleDiag] set FAILED source=$source requestedId=$id error=Bad state: synthetic selection refused',
              ),
            ),
            hasLength(1),
          );
          expect(d.player.state.track.subtitle.uri, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
  testWidgets(
    'subtitle forced metadata failure falls back to off without escaping its property-read catch',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          (p.platform as FakeNativePlayer).beforeOperation = (name, value) {
            if (name == 'getProperty' && value == 'track-list/count') {
              throw StateError('forced metadata unavailable');
            }
          };
        },
      );
      await d.initialize();
      await d.f.finish(t, SubtitleSettingsStorage.setSubtitleForcedOnly(true));
      try {
        await d.mount(publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.native.calls.where(
            (c) => c.$1 == 'getProperty' && c.$2 == 'track-list/count',
          ),
          hasLength(1),
        );
        expect(
          d.logs.where((s) => s.contains('forced-track metadata unavailable')),
          isEmpty,
        );
        expect(
          d.player.calls.where((c) => c.$1 == 'subtitle').map((c) => c.$2),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle malformed default-language storage is swallowed before selection',
    (t) async {
      final d = SubtitleApplyDriver(t, configurePlayer: seedLanguagePlayer);
      await d.initialize();
      final prefs = await d.f.finish(t, ProfilePreferences.instance());
      await d.f.finish(t, prefs.setInt('player_default_subtitle_language', 42));
      try {
        await d.mount(publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(
          d.logs.where(
            (s) =>
                s.startsWith('SubAuto: _applyDefaultSubtitleLanguage FAILED:'),
          ),
          hasLength(1),
        );
        expect(
          d.logs,
          contains(
            'SubAuto: restore done — embeddedSubtitleApplied=false → running addon auto-select',
          ),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle source priority catches malformed language after real addon discovery',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('malformed');
      await d.order(language: 'eng');
      final prefs = await d.f.finish(t, ProfilePreferences.instance());
      await d.f.finish(t, prefs.setInt('player_default_subtitle_language', 42));
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(d.requests(d.endpoint('malformed')), 1);
        expect(d.requests(d.caption('malformed')), 0);
        expect(
          d.logs.where(
            (s) => s.startsWith('SubAuto: source priority apply failed:'),
          ),
          isNotEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle discovery catches stable legacy inventory storage failure without native selection',
    (t) async {
      final d = SubtitleSourcesDriver(
        t,
        committed: false,
        configurePlayer: seedLanguagePlayer,
      );
      await d.setup();
      await d.register('inventory');
      await d.order(language: 'eng');
      final prefs = await d.f.finish(t, ProfilePreferences.instance());
      await d.f.finish(t, prefs.setInt('stremio_addons_v1', 42));
      StremioService.instance.invalidateCache();
      try {
        await d.mount(screen: priorityScreen, publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.calls.where((c) => c.$1 == 'subtitle'), isEmpty);
        expect(d.requests(d.endpoint('inventory')), 0);
        expect(d.requests(d.caption('inventory')), 0);
        expect(
          d.logs.where(
            (s) => s.startsWith('SubAuto: auto-select FAILED with exception:'),
          ),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle reported native sid failure retains the Dart selected track',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p, sid: '3');
          (p.platform as FakeNativePlayer).beforeOperation = (name, value) {
            if (name == 'getProperty' && value == 'sid') {
              throw StateError('sid unavailable');
            }
          };
        },
      );
      await d.initialize();
      try {
        await d.mount(publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, '3');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['3'],
        );
        expect(
          d.native.calls.where((c) => c.$1 == 'getProperty' && c.$2 == 'sid'),
          hasLength(1),
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle nonnative forced mode never inherits an unmarked full track',
    (t) async {
      final d = SubtitleApplyDriver(
        t,
        native: false,
        configurePlayer: (p) {
          p.state = p.state.copyWith(
            tracks: const mk.Tracks(subtitle: languageTracks),
            track: const mk.Track(
              subtitle: mk.SubtitleTrack('3', 'Spanish captions', 'spa'),
            ),
          );
        },
      );
      await d.initialize();
      await d.f.finish(t, SubtitleSettingsStorage.setSubtitleForcedOnly(true));
      try {
        await d.mount(publishTracks: false);
        await d.f.actions.settle(t);
        expect(d.player.state.track.subtitle.id, 'no');
        expect(
          d.player.calls
              .where((c) => c.$1 == 'subtitle')
              .map((c) => (c.$2 as mk.SubtitleTrack).id),
          ['no'],
        );
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
  testWidgets(
    'subtitle policy native property failure retains recognized track metadata for foreign-audio selection',
    (t) async {
      var reads = 0;
      final d = SubtitleSourcesDriver(
        t,
        configurePlayer: (p) {
          seedLanguagePlayer(p);
          final native = p.platform as FakeNativePlayer;
          native.beforeOperation = (name, value) {
            if (name == 'getProperty' && value == 'current-tracks/audio/lang') {
              if (++reads >= 2) {
                throw StateError('policy language unavailable');
              }
              native.properties['current-tracks/audio/lang'] = 'eng';
            }
          };
        },
      );
      await d.setup();
      await d.register('metadata-fallback');
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
        await d.f.actions.settle(t);
        expect(reads, 3);
        expect(d.player.state.track.audio.id, '2');
        expect(d.requests(d.caption('metadata-fallback')), 1);
        expect(d.player.state.track.subtitle.uri, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await removeFixture(d);
      }
    },
  );
}
