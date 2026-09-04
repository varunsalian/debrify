import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv/channel_stats.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/screens/debrify_tv/layouts/debrify_tv_view.dart';
import 'package:debrify/screens/debrify_tv/layouts/spotlight_layout.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/text_brightness.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_adapter.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The TV rail's contract after the utility move: Search, Add channel,
/// Import, Export and Settings sit in an icon row pinned under Quick Play —
/// reachable in one DOWN from the top, never behind the channel list.
void main() {
  testWidgets('TV utilities are one DOWN from Quick Play, ahead of the list', (
    tester,
  ) async {
    var settingsOpened = false;
    var exportOpened = false;
    final watched = <String>[];
    final entry = await _pumpTv(
      tester,
      onSettings: () => settingsOpened = true,
      onExport: () => exportOpened = true,
      onDeleteAll: _noop,
      onWatch: (channel) => watched.add(channel.id),
    );

    entry.requestFocus();
    await tester.pump();
    expect(entry.hasFocus, isTrue);

    // DOWN from Quick Play lands on the utility row (Search first); the
    // caption names the focused icon.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('Search'), findsOneWidget);

    // Export is a first-class DPAD action, immediately before Settings.
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    expect(find.text('Export'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(exportOpened, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Delete all'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(settingsOpened, isTrue);

    // DOWN drops into the channel list; RIGHT enters the stage at Tune in.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Tune in'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(watched, ['channel-0']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV search filters the rail and folds away clean', (
    tester,
  ) async {
    // Passthrough text mode: this test exercises the filter and the DPAD
    // run around the field, not the in-app keyboard (which has its own
    // tests).
    StorageService.tvKeyboardEnabledCached = false;
    addTearDown(() => StorageService.tvKeyboardEnabledCached = true);

    final watched = <String>[];
    final entry = await _pumpTv(
      tester,
      onWatch: (channel) => watched.add(channel.id),
    );

    entry.requestFocus();
    await tester.pump();

    // Quick Play -> Search icon -> OK unfolds the field, focused.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(field, findsOneWidget);

    await tester.enterText(field, '18');
    await tester.pump();
    expect(find.text('1 of 18 channels'), findsOneWidget);
    // The name shows on the rail row AND on the stage (the filter restaged
    // the first match).
    expect(find.text('Channel 18'), findsWidgets);
    expect(find.text('Channel 2'), findsNothing);

    // A query with no matches says so instead of showing an empty rail —
    // and the stage must NOT fall back to the first-run prompt.
    await tester.enterText(field, 'documentary');
    await tester.pump();
    expect(find.text('No channels match “documentary”'), findsOneWidget);
    expect(find.text('No channels match your search.'), findsOneWidget);
    expect(
      find.text('Make a channel out of anything you can name.'),
      findsNothing,
    );

    // DOWN from the field lands on the first (only) match; OK tunes it.
    await tester.enterText(field, '18');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(watched, ['channel-17']);

    // UP -> field, UP -> Search icon; OK folds the field away AND clears the
    // filter — a hidden query must never keep thinning the rail.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('18 channels'), findsOneWidget);
    expect(find.text('Channel 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<FocusNode> _pumpTv(
  WidgetTester tester, {
  VoidCallback? onSettings,
  VoidCallback? onExport,
  VoidCallback? onDeleteAll,
  ValueChanged<DebrifyTvChannel>? onWatch,
}) async {
  PlatformUtil.debugSetAndroidTvCached(true);
  addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
  tester.view.physicalSize = const Size(960, 540);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final entry = FocusNode(debugLabel: 'test-quick-play');
  addTearDown(entry.dispose);
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
            onExport: onExport ?? _noop,
            onDeleteAll: onDeleteAll ?? _noop,
            onSettings: onSettings ?? _noop,
            onWatch: onWatch ?? _noopChannel,
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
  return entry;
}

void _noop() {}

void _noopChannel(DebrifyTvChannel _) {}

void _noopTorrent(DebrifyTvChannel _, CachedTorrent __) {}
