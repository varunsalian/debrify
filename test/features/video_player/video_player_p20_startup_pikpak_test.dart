import 'package:debrify/features/video_player/application/vp_filename_hash.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/startup_driver.dart' show startupSource;

const _cold = 'https://dl.mypikpak.com/p20-cold.mp4';

List<Object?> _seeks(FakePlayer p) => [
  for (final c in p.calls)
    if (c.$1 == 'seek') c.$2,
];

List<String> _retryCalls(EngineDriver d) => [
  for (final l in d.logs)
    if (l.startsWith('PikPak: _playPikPakVideoWithRetry called')) l,
];

Future<void> _resume(EngineDriver d, String key, Duration at) =>
    d.f.finish<void>(
      d.t,
      VideoProgressStorage.saveVideoPlaybackState(
        videoTitle: key,
        videoUrl: _cold,
        positionMs: at.inMilliseconds,
        durationMs: const Duration(minutes: 20).inMilliseconds,
      ),
    );

Future<EngineDriver> _start(
  WidgetTester t,
  VideoPlayerScreen screen, {
  Future<void> Function(EngineDriver)? seed,
}) async {
  final d = EngineDriver(t);
  await d.initialize();
  if (seed != null) await seed(d);
  await d.mount(screen: screen);
  await d.f.actions.settle(t);
  return d;
}

void main() {
  for (final (label, entry) in [
    (
      'provider',
      const PlaylistEntry(
        url: _cold,
        title: 'Cold.Provider.mkv',
        provider: 'PikPak',
      ),
    ),
    (
      'file id',
      const PlaylistEntry(
        url: _cold,
        title: 'Cold.File.mkv',
        pikpakFileId: 'p20-cold',
      ),
    ),
  ]) {
    testWidgets(
      'P20 a PikPak playlist entry by $label starts through the cold-storage open and restores its resume',
      (t) async {
        // Only a `pikpak` provider row uses the file-id resume key.
        final key = vpFilenameHash(entry.title);
        final d = await _start(
          t,
          VideoPlayerScreen(
            videoUrl: _cold,
            title: 'P20 PikPak $label',
            playlist: [entry],
          ),
          seed: (d) => _resume(d, key, const Duration(minutes: 6)),
        );
        try {
          expect(_retryCalls(d), hasLength(1));
          expect(_retryCalls(d).single, endsWith('isDebrifyTV: false'));
          expect(_seeks(d.player), [const Duration(minutes: 6)]);
          expect(
            d.logs.where((l) => l.contains('[StartupFailover] event=')),
            isEmpty,
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P20 a PikPak percent start seeks to that share after the cold-storage readiness gate',
    (t) async {
      final d = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: _cold,
          title: 'P20 PikPak percent',
          startAtPercent: .25,
          playlist: [
            PlaylistEntry(
              url: _cold,
              title: 'Cold.Pct.mkv',
              provider: 'pikpak',
            ),
          ],
        ),
      );
      try {
        expect(_seeks(d.player), [const Duration(minutes: 5)]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P20 a PikPak random start seeks once inside the random share', (
    t,
  ) async {
    final d = await _start(
      t,
      const VideoPlayerScreen(
        videoUrl: _cold,
        title: 'P20 PikPak random',
        startFromRandom: true,
        randomStartMaxPercent: 10,
        playlist: [
          PlaylistEntry(url: _cold, title: 'Cold.Rnd.mkv', provider: 'pikpak'),
        ],
      ),
    );
    try {
      final seeks = _seeks(d.player);
      expect(seeks, hasLength(1));
      expect((seeks.first! as Duration) <= const Duration(minutes: 2), isTrue);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P20 a PikPak random start with no usable share falls back to the stored resume',
    (t) async {
      const entry = PlaylistEntry(
        url: _cold,
        title: 'Cold.Rnd0.mkv',
        provider: 'pikpak',
      );
      final d = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: _cold,
          title: 'P20 PikPak random none',
          startFromRandom: true,
          randomStartMaxPercent: 0,
          playlist: [entry],
        ),
        seed: (d) =>
            _resume(d, vpFilenameHash(entry.title), const Duration(minutes: 3)),
      );
      try {
        expect(_seeks(d.player), [const Duration(minutes: 3)]);
      } finally {
        await d.close();
      }
    },
  );

  for (final magic in [false, true]) {
    testWidgets(
      'P20 a PikPak URL without a playlist starts cold-storage with isDebrifyTV=$magic',
      (t) async {
        final d = await _start(
          t,
          VideoPlayerScreen(
            videoUrl: _cold,
            title: 'P20 PikPak url',
            requestMagicNext: magic ? () async => null : null,
          ),
        );
        try {
          expect(_retryCalls(d), hasLength(1));
          expect(_retryCalls(d).single, endsWith('isDebrifyTV: $magic'));
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P20 a non-PikPak playlist entry on a PikPak-looking URL keeps the ordinary open',
    (t) async {
      final d = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: _cold,
          title: 'P20 PikPak lookalike',
          playlist: [PlaylistEntry(url: _cold, title: 'Lookalike.mkv')],
        ),
      );
      try {
        expect(_retryCalls(d), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a PikPak launch commits its launch source after the readiness gate',
    (t) async {
      final commits = <String>[];
      final source = startupSource('p20-pikpak-launch', url: _cold);
      final d = await _start(
        t,
        VideoPlayerScreen(
          videoUrl: _cold,
          title: 'P20 PikPak commit',
          stremioSources: [source],
          stremioCurrentSourceIndex: 0,
          onStremioSourceCommitted: (s) async => commits.add(s.name),
        ),
      );
      try {
        expect(_retryCalls(d), hasLength(1));
        expect(commits, [source.name]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a PikPak start restores track preferences once, after the cold-storage gate',
    (t) async {
      final d = await _start(
        t,
        const VideoPlayerScreen(
          videoUrl: _cold,
          title: 'P20 PikPak tracks',
          playlist: [
            PlaylistEntry(
              url: _cold,
              title: 'Cold.Tracks.mkv',
              provider: 'pikpak',
            ),
          ],
        ),
      );
      try {
        expect(
          d.logs.where(
            (l) => l.startsWith('SubAuto: _restoreTrackPreferences entered'),
          ),
          hasLength(1),
        );
      } finally {
        await d.close();
      }
    },
  );
}
