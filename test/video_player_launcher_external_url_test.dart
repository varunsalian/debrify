import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tracker launch argument compatibility', () {
    test('legacy suppression alias preserves its original behavior', () {
      const args = VideoPlayerLaunchArgs(
        videoUrl: 'video',
        title: 'Title',
        suppressTraktAutoSync: true,
      );
      expect(args.suppressTraktAutoSync, isTrue);
      expect(args.suppressTrackerAutoSync, isTrue);
    });

    test('copyWith preserves Trakt and Simkl while enabling MDBList', () {
      const original = VideoPlayerLaunchArgs(
        videoUrl: 'video',
        title: 'Title',
        traktScrobble: true,
        traktProgressPercent: 21,
        simklScrobble: true,
        simklProgressPercent: 34,
        suppressTraktAutoSync: true,
      );
      final copy = original.copyWith(
        mdblistScrobble: true,
        mdblistProgressPercent: 55,
      );
      expect(copy.traktScrobble, isTrue);
      expect(copy.traktProgressPercent, 21);
      expect(copy.simklScrobble, isTrue);
      expect(copy.simklProgressPercent, 34);
      expect(copy.mdblistScrobble, isTrue);
      expect(copy.mdblistProgressPercent, 55);
      expect(copy.suppressTraktAutoSync, isTrue);

      final downgraded = copy.copyWith(mdblistScrobble: false);
      expect(downgraded.mdblistScrobble, isFalse);
      expect(downgraded.traktScrobble, isTrue);
      expect(downgraded.simklScrobble, isTrue);
    });

    test('MDBList tracking requires both sync and authentication', () {
      bool enabled({
        bool requested = true,
        bool autoEligible = false,
        bool featureEnabled = true,
        bool identityAvailable = true,
        bool syncEnabled = true,
        bool authenticated = true,
      }) => VideoPlayerLauncher.shouldEnableMdblistTracking(
        requested: requested,
        autoEligible: autoEligible,
        featureEnabled: featureEnabled,
        identityAvailable: identityAvailable,
        syncEnabled: syncEnabled,
        authenticated: authenticated,
      );

      expect(enabled(), isTrue);
      expect(enabled(syncEnabled: false), isFalse);
      expect(enabled(authenticated: false), isFalse);
      expect(enabled(featureEnabled: false), isFalse);
      expect(enabled(identityAvailable: false), isFalse);
      expect(enabled(requested: false, autoEligible: true), isTrue);
      expect(enabled(requested: false, autoEligible: false), isFalse);
    });

    test('copyWith and widget preserve startup validation intent', () {
      Future<void> commit(Torrent _) async {}

      final original = VideoPlayerLaunchArgs(
        videoUrl: 'video',
        title: 'Title',
        startupFailoverEnabled: true,
        startupResolverProvider: 'pikpak',
        onStremioSourceCommitted: commit,
      );

      final copy = original.copyWith(traktScrobble: true);
      expect(copy.startupFailoverEnabled, isTrue);
      expect(copy.startupResolverProvider, 'pikpak');
      expect(copy.onStremioSourceCommitted, same(commit));

      final widget = copy.toWidget();
      expect(widget.startupFailoverEnabled, isTrue);
      expect(widget.startupResolverProvider, 'pikpak');
      expect(widget.onStremioSourceCommitted, same(commit));
    });

    test('explicit launches do not opt into automatic startup failover', () {
      const args = VideoPlayerLaunchArgs(videoUrl: 'video', title: 'Title');

      expect(args.startupFailoverEnabled, isFalse);
      expect(args.toWidget().startupFailoverEnabled, isFalse);
    });
  });

  group('external playback URL selection', () {
    VideoPlayerLaunchArgs args({String? audioUrl, String? fallbackUrl}) {
      return VideoPlayerLaunchArgs(
        videoUrl: 'https://example.com/video-only.mp4',
        audioUrl: audioUrl,
        fallbackUrl: fallbackUrl,
        title: 'Video',
      );
    }

    test('uses muxed fallback when the primary stream has separate audio', () {
      final launchArgs = args(
        audioUrl: 'https://example.com/audio.m4a',
        fallbackUrl: 'https://example.com/muxed.mp4',
      );

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(launchArgs),
        'https://example.com/muxed.mp4',
      );
    });

    test('keeps primary URL for an already-muxed stream', () {
      final launchArgs = args(fallbackUrl: 'https://example.com/fallback.mp4');

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(launchArgs),
        'https://example.com/video-only.mp4',
      );
    });

    test('keeps primary URL when no muxed fallback is available', () {
      final launchArgs = args(audioUrl: 'https://example.com/audio.m4a');

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(launchArgs),
        'https://example.com/video-only.mp4',
      );
    });

    test('ignores empty audio and fallback URLs', () {
      final launchArgs = args(audioUrl: '', fallbackUrl: '');

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(launchArgs),
        'https://example.com/video-only.mp4',
      );
    });
  });

  group('external-player fallback notice', () {
    const authenticatedWebDav = VideoPlayerLaunchArgs(
      videoUrl: 'https://dav.example/video.mkv',
      title: 'Video',
      httpHeaders: {'Authorization': 'Basic redacted'},
      disableExternalPlayer: true,
    );

    test(
      'is shown for authenticated playback when external is the default',
      () {
        expect(
          VideoPlayerLauncher.shouldExplainExternalPlayerFallback(
            authenticatedWebDav,
            'external',
          ),
          isTrue,
        );
      },
    );

    test('is not shown when Debrify player is the default', () {
      expect(
        VideoPlayerLauncher.shouldExplainExternalPlayerFallback(
          authenticatedWebDav,
          'debrify',
        ),
        isFalse,
      );
    });

    test('is not shown for an unrelated external-player override', () {
      const localRecording = VideoPlayerLaunchArgs(
        videoUrl: 'file:///recording.ts',
        title: 'Recording',
        disableExternalPlayer: true,
      );
      expect(
        VideoPlayerLauncher.shouldExplainExternalPlayerFallback(
          localRecording,
          'external',
        ),
        isFalse,
      );
    });

    testWidgets('continues only when Use Debrify player is chosen', (
      tester,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const Scaffold();
            },
          ),
        ),
      );

      final result = VideoPlayerLauncher.showAuthenticatedWebDavPlayerNotice(
        context,
      );
      await tester.pumpAndSettle();
      expect(find.text('External player unavailable'), findsOneWidget);

      await tester.tap(find.text('Use Debrify player'));
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });

    testWidgets('Cancel aborts the fallback', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const Scaffold();
            },
          ),
        ),
      );

      final result = VideoPlayerLauncher.showAuthenticatedWebDavPlayerNotice(
        context,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });

    testWidgets('system Back aborts the fallback', (tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const Scaffold();
            },
          ),
        ),
      );

      final result = VideoPlayerLauncher.showAuthenticatedWebDavPlayerNotice(
        context,
      );
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    });
  });
}
