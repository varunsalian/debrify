import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv/channel_stats.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/screens/debrify_tv/layouts/debrify_tv_view.dart';
import 'package:debrify/screens/debrify_tv/layouts/spotlight_layout.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TV rail keeps its final utility actions visible and reachable', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final entry = FocusNode(debugLabel: 'test-quick-play');
    addTearDown(entry.dispose);
    var settingsOpened = false;
    final watched = <String>[];
    final channels = List<DebrifyTvChannel>.generate(
      18,
      (index) => DebrifyTvChannel(
        id: 'channel-$index',
        name: 'Channel ${index + 1}',
        keywords: ['keyword ${index + 1}'],
        avoidNsfw: true,
        channelNumber: index + 1,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

    final theme = AppThemes.byId('spotlight');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeAdapter.themed(theme, TextBrightness.bright),
        builder: (context, child) => AppThemeScope(theme: theme, child: child!),
        home: Scaffold(
          body: SpotlightLayout(
            bottomInset: 0,
            entryFocusNode: entry,
            view: DebrifyTvView(
              channels: channels,
              favoriteIds: const {},
              railHealth: const <String, DebrifyTvRailHealth>{},
              stats: null,
              busy: false,
              onQuickPlay: _noop,
              onAdd: _noop,
              onImport: _noop,
              onSettings: () => settingsOpened = true,
              onWatch: (channel) => watched.add(channel.id),
              onEdit: _noopChannel,
              onShare: _noopChannel,
              onDelete: _noopChannel,
              onToggleFavorite: _noopChannel,
              onChannelFocused: _noopChannel,
              onWatchOne: _noopTorrent,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    entry.requestFocus();
    await tester.pump();
    expect(entry.hasFocus, isTrue);

    // Quick Play -> 18 channels -> Add -> Import -> Settings.
    for (var i = 0; i < channels.length + 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.pumpAndSettle();

    final settings = find.text('Settings');
    expect(Focus.of(tester.element(settings)).hasFocus, isTrue);
    final settingsRect = tester.getRect(settings);
    expect(settingsRect.top, greaterThanOrEqualTo(0));
    expect(settingsRect.bottom, lessThanOrEqualTo(540));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(settingsOpened, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Tune in'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(watched, ['channel-17']);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

void _noopChannel(DebrifyTvChannel _) {}

void _noopTorrent(DebrifyTvChannel _, CachedTorrent __) {}
