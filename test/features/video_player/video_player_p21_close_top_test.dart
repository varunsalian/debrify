import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/sync_stepper_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';
import 'support/tv_episode_driver.dart' show episodeSource, tvDirectory;

VideoPlayerScreen _everything() => VideoPlayerScreen(
  videoUrl: 'https://p21.test/a.mp4',
  title: 'A',
  channelDirectory: tvDirectory,
  requestChannelById: (id) async => null,
  stremioSources: [episodeSource('P21 A'), episodeSource('P21 B')],
  stremioCurrentSourceIndex: 0,
  resolveStremioSource: (s) async => s.directUrl,
);

Future<P21Driver> _tv(WidgetTester t, {VideoPlayerScreen? screen}) async {
  final d = P21Driver(t, tv: true);
  await d.initialize();
  await d.mount(screen: screen ?? _everything());
  await d.wait(4000);
  return d;
}

/// Opens an overlay through the bar's own (hidden) callback.
Future<void> _open(P21Driver d, void Function() open) async {
  d.observe(open);
  await d.wait(60);
}

Finder get _menu => find.byType(PlayerMenuPanel);
Finder get _sync => find.byType(SyncStepperOverlay);
Finder get _debrify => find.byType(ChannelGuide);
Finder get _sources => find.byType(SourceSheet);
Finder get _stremio => find.byType(StremioTvGuideSheet);

void main() {
  p21Timeouts();

  for (final kind in ['debrify', 'stremio', 'sources']) {
    testWidgets(
      'P21 TV system BACK closes the open $kind overlay and returns focus to the root',
      (t) async {
        p21IgnoreGuideRowOverflow();
        final d = await _tv(
          t,
          screen: kind == 'stremio'
              ? P21Driver.screen(
                  stremioTvChannels: tvDirectory,
                  stremioTvChannelSwitchProvider: (id) async => null,
                )
              : null,
        );
        try {
          final finder = kind == 'debrify'
              ? _debrify
              : kind == 'stremio'
              ? _stremio
              : _sources;
          await _open(
            d,
            kind == 'sources' ? d.bar.onShowSources! : d.bar.onShowGuide!,
          );
          expect(finder, findsOneWidget);
          expect(d.focused, isNot('tvPlayerRoot'));
          await d.systemBack();
          await d.wait(400);
          expect(finder, findsNothing);
          expect(d.focused, 'tvPlayerRoot');
          expect(d.barUp, isFalse);
          expect(d.playerRouteOpen, isTrue);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV system BACK in the menu pane walks back to the rail, keeps focus, then closes to the root',
    (t) async {
      final d = await _tv(t, screen: P21Driver.screen());
      try {
        await d.menu();
        await d.key(LogicalKeyboardKey.arrowRight);
        final inMenu = d.focused;
        expect(inMenu, isNot('tvPlayerRoot'));
        await d.systemBack();
        await d.wait(350);
        expect(_menu, findsOneWidget, reason: 'the press changed pane');
        expect(d.focused, isNot('tvPlayerRoot'));
        await d.systemBack();
        await d.wait(350);
        expect(_menu, findsNothing);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.playerRouteOpen, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV the sync overlay opened from the menu sits above a still-open menu, which BACK closes first',
    (t) async {
      final d = await _tv(t, screen: P21Driver.screen());
      try {
        final panel = await d.menu();
        expect(panel.onSyncRequested, isNotNull);
        d.observe(panel.onSyncRequested!);
        await d.wait(350);
        expect(_sync, findsOneWidget);
        expect(d.focused, 'sync-stepper-overlay');
        // Pinned: the menu is still flagged open beneath the stepper, so the
        // first BACK closes it and takes focus to the root.
        await d.systemBack();
        await d.wait(350);
        expect(find.byType(PlayerMenuPanel, skipOffstage: false), findsNothing);
        expect(_sync, findsOneWidget);
        expect(d.focused, 'tvPlayerRoot');
        await d.systemBack();
        await d.wait(350);
        expect(_sync, findsNothing);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.playerRouteOpen, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV system BACK closes overlays from the top in menu, Debrify guide, source sheet order',
    (t) async {
      p21IgnoreGuideRowOverflow();
      final d = await _tv(t);
      try {
        await _open(d, d.bar.onShowSources!);
        await _open(d, d.bar.onShowGuide!);
        await d.menu();
        expect(_menu, findsOneWidget);
        expect(_debrify, findsOneWidget);
        expect(_sources, findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(_menu, findsNothing);
        expect(_debrify, findsOneWidget);
        expect(_sources, findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(_debrify, findsNothing);
        expect(_sources, findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(_sources, findsNothing);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV system BACK closes the menu, then the sync overlay, then the guide beneath them',
    (t) async {
      p21IgnoreGuideRowOverflow();
      final d = await _tv(t);
      try {
        await _open(d, d.bar.onShowGuide!);
        final panel = await d.menu();
        d.observe(panel.onSyncRequested!);
        await d.wait(350);
        expect(_sync, findsOneWidget);
        expect(_debrify, findsOneWidget);
        await d.systemBack();
        await d.wait(350);
        expect(_sync, findsOneWidget);
        expect(_debrify, findsOneWidget);
        await d.systemBack();
        await d.wait(350);
        expect(_sync, findsNothing);
        expect(_debrify, findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(_debrify, findsNothing);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV system BACK closes the Stremio guide after the source sheet above it',
    (t) async {
      final d = await _tv(
        t,
        screen: VideoPlayerScreen(
          videoUrl: 'https://p21.test/a.mp4',
          title: 'A',
          stremioTvChannels: tvDirectory,
          stremioTvChannelSwitchProvider: (id) async => null,
          stremioSources: [episodeSource('P21 A'), episodeSource('P21 B')],
          stremioCurrentSourceIndex: 0,
          resolveStremioSource: (s) async => s.directUrl,
        ),
      );
      try {
        await _open(d, d.bar.onShowGuide!);
        await _open(d, d.bar.onShowSources!);
        expect(_stremio, findsOneWidget);
        expect(_sources, findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(_sources, findsNothing);
        expect(_stremio, findsOneWidget);
        await d.systemBack();
        await d.wait(400);
        expect(_stremio, findsNothing);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV system BACK closes the IPTV sheet through its own back contract and focuses the root',
    (t) async {
      final channels = [P21Driver.channel(0), P21Driver.channel(1)];
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(
          screen: P21Driver.iptv(channels),
          settleInitialization: false,
        );
        await d.wait(4000);
        await d.key(LogicalKeyboardKey.arrowUp);
        await d.wait(400);
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

  for (final key in [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowRight,
  ]) {
    testWidgets(
      'P21 TV system BACK after ${key.keyLabel} inside the IPTV sheet changes its pane and keeps it open with focus',
      (t) async {
        final channels = [P21Driver.channel(0), P21Driver.channel(1)];
        final d = P21Driver(t, tv: true);
        await d.initialize();
        try {
          await d.mount(
            screen: P21Driver.iptv(channels),
            settleInitialization: false,
          );
          await d.wait(4000);
          await d.key(LogicalKeyboardKey.arrowUp);
          await d.wait(400);
          await d.key(key);
          await d.wait(400);
          await d.systemBack();
          await d.wait(400);
          expect(find.byType(IptvChannelSheet), findsOneWidget);
          expect(d.focused, isNot('tvPlayerRoot'));
          expect(
            FocusManager.instance.primaryFocus!.context!
                .findAncestorWidgetOfExactType<IptvChannelSheet>(),
            isNotNull,
            reason: 'focus stays with the sheet',
          );
          expect(d.playerRouteOpen, isTrue);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final tv in [false, true]) {
    testWidgets(
      'P21 ${tv ? 'TV' : 'desktop'} opening the menu ${tv ? 'releases' : 'keeps'} root focus before the panel frame',
      (t) async {
        final d = P21Driver(t, tv: tv);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          d.root.requestFocus();
          await d.wait(0);
          expect(d.focused, 'tvPlayerRoot');
          d.observe(
            () => tv ? d.bar.onShowTracks() : d.controls.onShowTracks(),
          );
          await t.idle();
          expect(_menu, findsNothing, reason: 'no panel frame has run');
          expect(
            FocusManager.instance.primaryFocus,
            tv ? isNot(same(d.root)) : same(d.root),
          );
          await d.wait(350);
          expect(_menu, findsOneWidget);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
