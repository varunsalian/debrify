import 'dart:async';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:flutter/widgets.dart';
import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

/// Phase 17 original channel-switch state that the earlier P17 suites did not
/// pin: the outgoing item's subtitle state (sync offset, menu) is reset by
/// every TV channel switch, the switched stream becomes the resume identity,
/// and a failed Debrify open still ends the TV transition.
void main() {
  nextMetadataCases();
  bannerAndRandomCases();
  const a = 'https://player.test/a.mp4';
  const b = 'https://player.test/b.mp4';

  VideoPlayerScreen screen(String route) => VideoPlayerScreen(
    videoUrl: a,
    title: 'Film A',
    channelDirectory: route == 'Stremio' ? null : tvDirectory,
    requestChannelById: route == 'by id'
        ? (id) async => {'firstUrl': b, 'firstTitle': 'Film B'}
        : null,
    requestNextChannel: route == 'next'
        ? () async => {'firstUrl': b, 'firstTitle': 'Film B'}
        : null,
    stremioTvChannels: route == 'Stremio' ? tvDirectory : null,
    stremioTvChannelSwitchProvider: route == 'Stremio'
        ? (id) async => null
        : null,
  );

  Future<void> switchChannel(
    TvEpisodeDriver d,
    WidgetTester t,
    String route,
  ) async {
    if (route == 'next') {
      await d.nextChannel();
    } else if (route == 'by id') {
      final g = await d.debrifyGuide();
      await d.byId(g, g.channels.last);
    } else {
      final g = await d.stremioGuide();
      await d.stremioPick(g, 'b', url: b);
    }
    await d.f.advance(t);
  }

  for (final route in ['by id', 'next', 'Stremio']) {
    testWidgets(
      'P17 $route switch resets the outgoing subtitle sync offset and closes the menu',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(screen: screen(route));
          final panel = await d.menu();
          panel.onSubtitleStyleChanged!(
            const SubtitleSettingsData(
              sizeIndex: 0,
              colorIndex: 0,
              bgIndex: 0,
              styleIndex: 0,
              syncOffsetMs: 1500,
            ),
          );
          await d.f.advance(t);
          expect(d.native.properties['sub-delay'], '1.500');
          panel.onClose();
          await d.f.advance(t);
          expect(find.byType(PlayerMenuPanel), findsNothing);
          await switchChannel(d, t, route);
          expect(d.opens.last.uri, b);
          expect(d.native.properties['sub-delay'], '0.000');
          expect(find.byType(PlayerMenuPanel), findsNothing);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P17 $route switch files a later checkpoint under the switched stream URL',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(screen: screen(route));
          await switchChannel(d, t, route);
          expect(d.opens.last.uri, b);
          d.player.state = d.player.state.copyWith(
            duration: const Duration(minutes: 40),
            position: const Duration(minutes: 5),
          );
          d.player.emit('duration', d.player.state.duration);
          d.player.emit('position', d.player.state.position);
          await d.f.advance(t, const Duration(seconds: 2));
          playerControls(t).onPlayPause();
          await d.f.actions.settle(t);
          final saved = await d.f.finish(
            t,
            VideoProgressStorage.getVideoPlaybackState(
              // Stremio TV adopts the picked channel's title as its identity.
              videoTitle: route == 'Stremio' ? 'Channel b' : 'Film A',
            ),
          );
          // The switched stream is the checkpoint's URL identity; the launch
          // URL must not be filed for the switched channel.
          expect(saved?['url'], b);
          expect(saved?['positionMs'], 300000);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final route in ['by id', 'next']) {
    testWidgets(
      'P17 Debrify $route open failure ends the TV transition after its failure plate',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        TvControls controls() => t.widget<TvControls>(find.byType(TvControls));
        try {
          PlatformUtil.debugSetAndroidTvCached(true);
          await d.mount(screen: screen(route));
          ChannelGuideHandle? guide;
          if (route == 'by id') {
            controls().onShowGuide!();
            await d.f.advance(t);
            guide = ChannelGuideHandle(
              t.widget<ChannelGuide>(find.byType(ChannelGuide)),
            );
          }
          d.player.failures['open'] = StateError('open failed');
          final pause = Completer<void>();
          var entered = false;
          d.player.beforeOperation = (name, value) async {
            if (name == 'pause' && !entered) {
              entered = true;
              await pause.future;
            }
          };
          final dynamic action = route == 'by id'
              ? guide!.selectLast
              : controls().onNextChannel!;
          final task = d.observe<dynamic>(() => action()) as Future<dynamic>;
          await d.f.until(t, () => entered);
          await d.f.advance(t);
          expect(controls().isTransitioning, isTrue);
          pause.complete();
          await d.f.finish(t, task);
          await d.f.advance(t);
          expect(controls().isTransitioning, isFalse);
          expect(d.player.state.playlist.medias.single.uri, a);
        } finally {
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
}

void nextMetadataCases() {
  const b = 'https://player.test/b.mp4';
  for (final field in ['channelId', 'channelNumber', 'channelName']) {
    testWidgets(
      'P17 Debrify next with only $field adopts exactly that channel metadata',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Film A',
              channelDirectory: tvDirectory,
              showChannelName: true,
              channelName: 'Alpha',
              channelNumber: 7,
              requestChannelById: (id) async => null,
              requestNextChannel: () async => {
                'url': b,
                if (field == 'channelId') 'channelId': 'b',
                if (field == 'channelNumber') 'channelNumber': 12,
                if (field == 'channelName') 'channelName': 'Cinema',
              },
            ),
          );
          await d.nextChannel();
          expect(d.opens.last.uri, b);
          final g = await d.debrifyGuide();
          expect(g.currentChannelId, field == 'channelId' ? 'b' : 'a');
          expect(g.currentChannelNumber, field == 'channelNumber' ? 12 : 7);
          final plate = t
              .widgetList<DebrifyTvBanner>(find.byType(DebrifyTvBanner))
              .first;
          expect(
            plate.channelName,
            field == 'channelName' ? 'Cinema' : 'Alpha',
          );
          expect(plate.channelNumber, field == 'channelNumber' ? 12 : 7);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final payload in ['null', 'throw', 'empty url']) {
    testWidgets(
      'P17 Debrify next $payload provider result ends the TV transition',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        TvControls controls() => t.widget<TvControls>(find.byType(TvControls));
        try {
          PlatformUtil.debugSetAndroidTvCached(true);
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Film A',
              channelDirectory: tvDirectory,
              requestChannelById: (id) async => null,
              requestNextChannel: () async {
                if (payload == 'throw') throw StateError('next rejected');
                if (payload == 'null') return null;
                return {'url': '', 'channelId': 'b'};
              },
            ),
          );
          final pause = Completer<void>();
          var entered = false;
          d.player.beforeOperation = (name, value) async {
            if (name == 'pause' && !entered) {
              entered = true;
              await pause.future;
            }
          };
          final dynamic action = controls().onNextChannel!;
          final task = d.observe<dynamic>(() => action()) as Future<dynamic>;
          await d.f.until(t, () => entered);
          await d.f.advance(t);
          expect(controls().isTransitioning, isTrue);
          pause.complete();
          await d.f.finish(t, task);
          await d.f.advance(t);
          expect(controls().isTransitioning, isFalse);
          expect(
            d.player.state.playlist.medias.single.uri,
            'https://player.test/a.mp4',
          );
        } finally {
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
}

void bannerAndRandomCases() {
  const b = 'https://player.test/b.mp4';
  Iterable<DebrifyTvBanner> floating(WidgetTester t) => t
      .widgetList<DebrifyTvBanner>(find.byType(DebrifyTvBanner))
      .where((v) => !v.flush);
  VideoPlayerScreen screen() => VideoPlayerScreen(
    videoUrl: 'https://player.test/a.mp4',
    title: 'Film A',
    showChannelName: true,
    channelName: 'Alpha',
    requestNextChannel: () async => {'url': b, 'channelName': 'Beta'},
  );
  testWidgets(
    'P17 Debrify next with channel metadata raises the floating banner again after the launch banner faded',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: screen());
        await d.f.advance(t, const Duration(seconds: 8));
        expect(floating(t), isEmpty);
        await d.nextChannel();
        expect(floating(t).map((v) => v.channelName), ['Beta']);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 controls opening during the banner fade unmount the floating copy at once',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: screen());
        await d.f.advance(t, const Duration(seconds: 8));
        await d.nextChannel();
        expect(floating(t), hasLength(1));
        // Let the display window lapse: the banner starts its 350 ms fade but
        // stays mounted until the fade ends.
        double opacity() => t
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byWidgetPredicate(
                      (w) => w is DebrifyTvBanner && !w.flush,
                    ),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity;
        await d.f.advance(t, VideoPlayerTimingConstants.badgeDisplayDuration);
        await d.f.until(t, () => opacity() == 0);
        expect(floating(t), hasLength(1));
        // One frame, well inside the fade: the floating copy must already be
        // gone rather than left to finish fading under the dock.
        await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await t.pump(const Duration(milliseconds: 16));
        expect(floating(t), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 Debrify next random start waits for the switched stream duration before seeking',
    (t) async {
      var opens = 0;
      late final dynamic fake;
      final d = TvEpisodeDriver(
        t,
        configurePlayer: (player) {
          fake = player;
          player.onOpen = () {
            opens++;
            // Launch media never publishes a duration; the switched stream's
            // duration arrives only after its open returns.
            if (opens == 1) player.publishFrame(duration: Duration.zero);
          };
        },
      );
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Film A',
            startFromRandom: true,
            randomStartMaxPercent: 50,
            requestNextChannel: () async => {'url': b},
          ),
          // No launch duration, so the autosave timer never starts.
          settleInitialization: false,
        );
        await d.f.advance(t, const Duration(seconds: 1));
        final before = d.seeks.length;
        final task = d.beginNextChannel();
        await d.f.until(t, () => opens == 2);
        await d.f.advance(t, const Duration(milliseconds: 300));
        expect(d.seeks.skip(before), isEmpty);
        fake.publishFrame(duration: const Duration(minutes: 40));
        await d.f.finish<dynamic>(t, task);
        final seeks = d.seeks.skip(before).toList();
        expect(seeks, hasLength(1));
        expect(seeks.single.inMilliseconds, inInclusiveRange(1, 1200000));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

/// Holds a rendered Debrify guide so its selection callback can be invoked
/// directly, the way the guide row's Select would.
class ChannelGuideHandle {
  ChannelGuideHandle(this.guide);
  final dynamic guide;
  Future<void> selectLast() async {
    final dynamic callback = guide.onChannelSelected;
    await callback(guide.channels.last);
  }
}
