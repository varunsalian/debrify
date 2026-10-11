import 'dart:async';

import 'package:debrify/models/stremio_subtitle.dart';
import 'package:debrify/screens/video_player/widgets/subtitle_line_picker_overlay.dart';
import 'package:debrify/services/storage/track_preferences_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart' as mk;

import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_subtitle_test.dart'
    show prepare, preferences, subtitleScreen;

const decoderError = mk.PlayerLog(
  prefix: 'sub',
  level: 'error',
  text: 'subtitle decoder failed',
);

Future<void> drainRollback(
  WidgetTester tester,
  VideoPlayerEnvironment fixture,
  String id,
) async {
  await fixture.until(
    tester,
    () => fixture.player.state.track.subtitle.id == id,
  );
  for (var i = 0; i < 10; i++) {
    await fixture.advance(tester, const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets(
    'audio write during pending subtitle apply is not owned by unfinished attempt',
    (tester) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await prepare(tester, fixture);
      final delayed = Completer<void>();
      try {
        final menu = await openPlayerMenu(tester, fixture);
        fixture.player.delays['subtitle'] = delayed;
        final apply = menu.onEmbeddedSubtitleSelected('2', '1');
        await fixture.until(
          tester,
          () => fixture.player.calls.any(
            (call) =>
                call.$1 == 'subtitle' &&
                (call.$2 as mk.SubtitleTrack).id == '2',
          ),
        );
        await fixture.finish(tester, menu.onAudioSelected('2', '2'));
        expect((await preferences(tester))?['subtitleTrackId'], '2');
        fixture.player.failures['subtitle'] = StateError(
          'pending apply rejected',
        );
        fixture.player.delays.remove('subtitle');
        delayed.complete();
        expect(await fixture.finish(tester, apply), isFalse);
        expect(fixture.player.state.track.subtitle.id, '1');
        expect((await preferences(tester))?['subtitleTrackId'], '2');
        expect((await preferences(tester))?['audioTrackId'], '2');
      } finally {
        fixture.player.delays.remove('subtitle');
        if (!delayed.isCompleted) delayed.complete();
        await fixture.close(tester);
      }
    },
  );
  testWidgets('data subtitle rejection redacts contents in diagnostic id', (
    tester,
  ) async {
    final fixture = VideoPlayerEnvironment(native: true);
    await prepare(tester, fixture);
    const contents = '1\n00:00:01,000 --> 00:00:02,000\nPRIVATE CAPTION\n';
    final data = mk.SubtitleTrack.data(contents, title: 'Data captions');
    fixture.player.publishTracks(
      mk.Tracks(
        audio: fixture.player.state.tracks.audio,
        subtitle: [const mk.SubtitleTrack('1', 'English', 'eng'), data],
      ),
    );
    await fixture.advance(tester);
    final logs = <String>[];
    final oldPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      final menu = await openPlayerMenu(tester, fixture);
      fixture.player.failures['subtitle'] = StateError('data rejected');
      expect(
        await fixture.finish(
          tester,
          menu.onEmbeddedSubtitleSelected(data.id, '1'),
        ),
        isFalse,
      );
      expect(
        logs.where((line) => line.contains('set FAILED')).single,
        contains('requestedId=<external>'),
      );
      expect(
        logs.where((line) => line.contains('set FAILED')).single,
        isNot(contains(contents)),
      );
      expect(
        logs.where((line) => line.contains('user notified')).single,
        contains('source=player-menu-embedded reason='),
      );
      expect(fixture.player.state.track.subtitle.id, '1');
      expect(await preferences(tester), isNull);
    } finally {
      debugPrint = oldPrint;
      await fixture.close(tester);
    }
  });

  testWidgets('uri subtitle rejection redacts file path in diagnostic id', (
    tester,
  ) async {
    final fixture = VideoPlayerEnvironment(native: true);
    await prepare(tester, fixture);
    const sub = StremioSubtitle(
      id: 'rejected-uri',
      url: 'https://player.test/rejected-uri.srt',
      lang: 'eng',
      source: 'Fixture captions',
    );
    fixture.network.replies[sub.url] = http.Response(
      '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
      200,
    );
    final logs = <String>[];
    final oldPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      final menu = await openPlayerMenu(tester, fixture);
      fixture.player.failures['subtitle'] = StateError('uri rejected');
      expect(
        await fixture.finish(tester, menu.onAddonSubtitleSelected(sub, '1')),
        isFalse,
      );
      final diagnostic = logs
          .where((line) => line.contains('set FAILED'))
          .single;
      expect(diagnostic, contains('requestedId=<external>'));
      expect(
        logs.where((line) => line.contains('user notified')).single,
        contains('source=addon-external reason='),
      );
      expect(
        diagnostic,
        isNot(contains('requestedId=${fixture.directory.path}')),
      );
      expect(fixture.player.state.track.subtitle.id, '1');
      expect(await preferences(tester), isNull);
    } finally {
      debugPrint = oldPrint;
      await fixture.close(tester);
    }
  });

  testWidgets(
    'data apply does not claim an embedded preference as addon persistence',
    (tester) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await prepare(tester, fixture);
      final data = mk.SubtitleTrack.data(
        '1\n00:00:01,000 --> 00:00:02,000\nFixture\n',
        title: 'Data captions',
      );
      fixture.player.publishTracks(
        mk.Tracks(
          audio: fixture.player.state.tracks.audio,
          subtitle: [const mk.SubtitleTrack('1', 'English', 'eng'), data],
        ),
      );
      await fixture.advance(tester);
      try {
        final menu = await openPlayerMenu(tester, fixture);
        expect(
          await fixture.finish(
            tester,
            menu.onEmbeddedSubtitleSelected(data.id, '1'),
          ),
          isTrue,
        );
        final saved = await preferences(tester);
        expect(saved?['subtitleTrackId'], data.id);
        fixture.player.emit('log', decoderError);
        await drainRollback(tester, fixture, '1');
        expect(await preferences(tester), saved);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'automatic restored subtitle failure leaves saved preference untouched',
    (tester) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await tester.runAsync(fixture.initialize);
      await tester.runAsync(
        () => TrackPreferencesStorage.saveVideoTrackPreferences(
          videoTitle: subtitleScreen.title,
          audioTrackId: '1',
          subtitleTrackId: '1',
        ),
      );
      try {
        await fixture.mount(tester, subtitleScreen);
        expect(fixture.player.state.track.subtitle.id, '1');
        expect(
          fixture.player.calls
              .where((call) => call.$1 == 'subtitle')
              .map((call) => (call.$2 as mk.SubtitleTrack).id),
          contains('1'),
        );
        final savedBefore = await preferences(tester);
        fixture.player.emit('log', decoderError);
        await drainRollback(tester, fixture, 'no');
        expect(await preferences(tester), savedBefore);
        expect(find.textContaining('Couldn’t apply subtitles'), findsOneWidget);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  for (final mode in ['off', 'external', 'embedded']) {
    final off = mode == 'off';
    testWidgets('$mode attempt ignores unrelated audio preference identity', (
      tester,
    ) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await prepare(tester, fixture);
      final previousId = mode == 'external' ? 'stremio-malformed' : '1';
      if (mode == 'external') {
        fixture.player.publishTracks(
          mk.Tracks(
            audio: fixture.player.state.tracks.audio,
            subtitle: [
              ...fixture.player.state.tracks.subtitle,
              mk.SubtitleTrack(previousId, 'Previous embedded captions', 'eng'),
            ],
          ),
          selected: mk.Track(
            audio: fixture.player.state.track.audio,
            subtitle: mk.SubtitleTrack(
              previousId,
              'Previous embedded captions',
              'eng',
            ),
          ),
        );
        await fixture.advance(tester);
      }
      const sub = StremioSubtitle(
        id: 'online-race',
        url: 'https://player.test/race.srt',
        lang: 'eng',
        source: 'Fixture captions',
      );
      fixture.network.replies[sub.url] = http.Response(
        '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
        200,
      );
      try {
        final menu = await openPlayerMenu(tester, fixture);
        expect(
          await fixture.finish(
            tester,
            off
                ? menu.onSubtitlesOff('1')
                : mode == 'external'
                ? menu.onAddonSubtitleSelected(sub, '1')
                : menu.onEmbeddedSubtitleSelected('2', '1'),
          ),
          isTrue,
        );
        expect(
          (await preferences(tester))?['subtitleTrackId'],
          off
              ? 'no'
              : mode == 'external'
              ? 'stremio:online-race'
              : '2',
        );
        // The original audio callback accepts a selection snapshot. A native
        // track update or a stale pane can supply a different subtitle id;
        // that write must not acquire the earlier apply attempt's ownership.
        final unrelated = menu.selectedSubtitleId;
        expect(unrelated, previousId);
        await fixture.finish(tester, menu.onAudioSelected('2', unrelated));
        expect((await preferences(tester))?['subtitleTrackId'], unrelated);
        expect((await preferences(tester))?['audioTrackId'], '2');
        fixture.player.emit('log', decoderError);
        await drainRollback(tester, fixture, previousId);
        final saved = await preferences(tester);
        expect(saved?['subtitleTrackId'], previousId);
        expect(saved?['audioTrackId'], '1');
        expect(fixture.player.state.track.audio.id, '2');
      } finally {
        await fixture.close(tester);
      }
    });
  }

  testWidgets('late embedded failure restores previous addon selection once', (
    tester,
  ) async {
    final fixture = VideoPlayerEnvironment(native: true);
    await prepare(tester, fixture);
    const sub = StremioSubtitle(
      id: 'previous-addon',
      url: 'https://player.test/previous.srt',
      lang: 'eng',
      source: 'Fixture captions',
    );
    fixture.network.replies[sub.url] = http.Response(
      '1\n00:00:01,000 --> 00:00:02,000\nPrevious\n',
      200,
    );
    try {
      final menu = await openPlayerMenu(tester, fixture);
      expect(
        await fixture.finish(tester, menu.onAddonSubtitleSelected(sub, '1')),
        isTrue,
      );
      final previousTrack = fixture.player.state.track.subtitle;
      expect(
        await fixture.finish(tester, menu.onEmbeddedSubtitleSelected('2', '1')),
        isTrue,
      );
      fixture.player.calls.clear();
      fixture.player.emit('log', decoderError);
      await drainRollback(tester, fixture, previousTrack.id);
      fixture.player.emit('log', decoderError);
      await fixture.advance(tester, const Duration(milliseconds: 100));
      expect(
        fixture.player.calls
            .where((call) => call.$1 == 'subtitle')
            .map((call) => call.$2),
        [previousTrack],
      );
      expect(
        (await preferences(tester))?['subtitleTrackId'],
        'stremio:previous-addon',
      );
      expect((await preferences(tester))?['audioTrackId'], '1');
      menu.onSyncRequested!();
      await fixture.until(
        tester,
        () => find.byType(SubtitleLinePickerOverlay).evaluate().isNotEmpty,
      );
      expect(
        tester
            .widget<SubtitleLinePickerOverlay>(
              find.byType(SubtitleLinePickerOverlay),
            )
            .subtitleFilePath,
        previousTrack.id,
      );
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'superseded subtitle apply cannot roll back newer accepted selection',
    (tester) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await prepare(tester, fixture);
      try {
        final menu = await openPlayerMenu(tester, fixture);
        expect(
          await fixture.finish(
            tester,
            menu.onEmbeddedSubtitleSelected('2', '1'),
          ),
          isTrue,
        );
        expect(await fixture.finish(tester, menu.onSubtitlesOff('1')), isTrue);
        fixture.player.emit('log', decoderError);
        await drainRollback(tester, fixture, '2');
        expect((await preferences(tester))?['subtitleTrackId'], '2');
        expect((await preferences(tester))?['audioTrackId'], '1');
      } finally {
        await fixture.close(tester);
      }
    },
  );
}
