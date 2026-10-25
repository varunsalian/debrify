import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';
import 'support/tv_episode_driver.dart' show episodeSource, tvDirectory;

const _hide = Duration(seconds: 3);

final _channels = [P21Driver.channel(0), P21Driver.channel(1)];

/// A session offering every guide this case asks for.
VideoPlayerScreen _session({
  List<IptvChannel>? iptv,
  bool debrify = false,
  bool lookup = true,
  bool stremio = false,
  bool stremioProvider = true,
  bool sources = false,
}) => VideoPlayerScreen(
  videoUrl: iptv != null && iptv.isNotEmpty
      ? iptv.first.url
      : 'https://p21-guards.test/a.mp4',
  title: 'P21 guards',
  iptvChannels: iptv,
  iptvStartIndex: 0,
  iptvSourceId: iptv == null ? null : 'p21-source',
  channelDirectory: debrify ? tvDirectory : null,
  requestChannelById: debrify && lookup ? (id) async => null : null,
  stremioTvChannels: stremio ? tvDirectory : null,
  stremioTvChannelSwitchProvider: stremio && stremioProvider
      ? (id) async => null
      : null,
  stremioSources: sources
      ? [episodeSource('P21 A'), episodeSource('P21 B')]
      : null,
  stremioCurrentSourceIndex: sources ? 0 : null,
  resolveStremioSource: sources ? (s) async => s.directUrl : null,
);

Future<P21Driver> _mount(
  WidgetTester t,
  VideoPlayerScreen screen, {
  bool tv = false,
}) async {
  final d = P21Driver(t, tv: tv);
  await d.initialize();
  await d.mount(screen: screen, settleInitialization: false);
  await d.wait(4000);
  return d;
}

Future<void> _open(P21Driver d, void Function() open) async {
  d.observe(open);
  await d.wait(400);
}

int _armed(P21Driver d) => d.timers.where((v) => v.duration == _hide).length;

/// A desktop pointer moving under an open overlay neither raises the dock
/// nor starts a countdown.
Future<void> _expectPointerBlocked(P21Driver d) async {
  expect(d.barUp, isFalse);
  final armed = _armed(d);
  await d.hover();
  await d.wait(100);
  expect(d.barUp, isFalse);
  expect(_armed(d), armed);
  expect(d.activeTimers(_hide), 0);
}

/// Phase 21a Step 0c, class 6: the pointer-wake guard for every overlay
/// kind, close-top precedence between overlays that can be open together,
/// and which guide UP opens for each mix of IPTV, Stremio and Debrify TV.
void main() {
  p21Timeouts();

  for (final kind in ['sources', 'debrify', 'stremio', 'iptv']) {
    testWidgets(
      'P21 desktop a pointer wake under the open $kind overlay neither raises the dock nor arms a countdown',
      (t) async {
        p21IgnoreGuideRowOverflow();
        final d = await _mount(
          t,
          _session(
            iptv: kind == 'iptv' ? _channels : null,
            debrify: kind == 'debrify',
            stremio: kind == 'stremio',
            sources: kind == 'sources',
          ),
        );
        try {
          await _open(d, switch (kind) {
            'sources' => d.controls.onShowStremioSources!,
            'iptv' => d.controls.onShowIptvChannels!,
            _ => d.controls.onShowGuide!,
          });
          expect(switch (kind) {
            'sources' => find.byType(SourceSheet),
            'debrify' => find.byType(ChannelGuide),
            'stremio' => find.byType(StremioTvGuideSheet),
            _ => find.byType(IptvChannelSheet),
          }, findsOneWidget);
          await _expectPointerBlocked(d);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 desktop a pointer wake under the sync overlay alone neither raises the dock nor arms a countdown',
    (t) async {
      final d = await _mount(t, P21Driver.screen());
      try {
        final panel = await d.menu();
        d.observe(panel.onSyncRequested!);
        await d.wait(350);
        d.observe(panel.onClose);
        await d.wait(350);
        expect(find.byType(SyncStepperOverlay), findsOneWidget);
        await _expectPointerBlocked(d);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV system BACK closes the Debrify guide before the IPTV sheet beneath it',
    (t) async {
      p21IgnoreGuideRowOverflow();
      final d = await _mount(
        t,
        _session(iptv: _channels, debrify: true),
        tv: true,
      );
      try {
        await _open(d, d.bar.onShowIptvChannels!);
        await _open(d, d.bar.onShowGuide!);
        expect(find.byType(IptvChannelSheet), findsOneWidget);
        expect(find.byType(ChannelGuide), findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(find.byType(ChannelGuide), findsNothing);
        expect(find.byType(IptvChannelSheet), findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(find.byType(IptvChannelSheet), findsNothing);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.playerRouteOpen, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV system BACK closes the IPTV sheet before the source sheet beneath it',
    (t) async {
      final d = await _mount(
        t,
        _session(iptv: _channels, sources: true),
        tv: true,
      );
      try {
        await _open(d, d.bar.onShowSources!);
        await _open(d, d.bar.onShowIptvChannels!);
        expect(find.byType(SourceSheet), findsOneWidget);
        expect(find.byType(IptvChannelSheet), findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(find.byType(IptvChannelSheet), findsNothing);
        expect(find.byType(SourceSheet), findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(find.byType(SourceSheet), findsNothing);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final setup in [
    (
      debrify: false,
      lookup: true,
      stremio: true,
      provider: true,
      want: 'stremio',
    ),
    (
      debrify: true,
      lookup: true,
      stremio: false,
      provider: true,
      want: 'debrify',
    ),
    (
      debrify: true,
      lookup: false,
      stremio: false,
      provider: true,
      want: 'iptv',
    ),
    (
      debrify: false,
      lookup: true,
      stremio: true,
      provider: false,
      want: 'iptv',
    ),
  ]) {
    testWidgets(
      'P21 TV UP on an IPTV session that also has debrify=${setup.debrify} lookup=${setup.lookup} stremio=${setup.stremio} provider=${setup.provider} opens the ${setup.want} guide',
      (t) async {
        p21IgnoreGuideRowOverflow();
        final d = await _mount(
          t,
          _session(
            iptv: _channels,
            debrify: setup.debrify,
            lookup: setup.lookup,
            stremio: setup.stremio,
            stremioProvider: setup.provider,
          ),
          tv: true,
        );
        try {
          await d.key(LogicalKeyboardKey.arrowUp);
          await d.wait(100);
          expect(
            find.byType(ChannelGuide),
            setup.want == 'debrify' ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(StremioTvGuideSheet),
            setup.want == 'stremio' ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(IptvChannelSheet),
            setup.want == 'iptv' ? findsOneWidget : findsNothing,
          );
          expect(d.barUp, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV UP with an empty IPTV channel list raises the bar instead of opening a sheet',
    (t) async {
      final d = await _mount(t, _session(iptv: const []), tv: true);
      try {
        await d.key(LogicalKeyboardKey.arrowUp);
        await d.wait(100);
        expect(find.byType(IptvChannelSheet), findsNothing);
        expect(d.barUp, isTrue);
        expect(d.focused, 'tvPlayPause');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
