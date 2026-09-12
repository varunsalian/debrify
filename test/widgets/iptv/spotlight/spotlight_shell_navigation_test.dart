import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_category_control.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_content_type_control.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_rail.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

IptvPlaylist _playlist(String id, String name, String url) =>
    IptvPlaylist(id: id, name: name, url: url, addedAt: DateTime(2026, 1, 1));

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const t = IptvStyleTokens.spotlight;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: t.bg,
        body: Center(child: child),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('category is prominent, semantic and activates once from OK', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var opened = 0;
    var options = 0;
    final node = FocusNode(debugLabel: 'category');
    addTearDown(node.dispose);

    await _pump(
      tester,
      SizedBox(
        width: 500,
        child: SpotlightCategoryControl(
          categoryLabel: 'All channels',
          channelCount: 26,
          focusNode: node,
          onPressed: () => opened++,
          onOpenOptions: () => options++,
        ),
      ),
    );

    expect(find.text('CATEGORY'), findsOneWidget);
    expect(find.text('All channels · 26'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Category, All channels, 26 channels'),
      findsOneWidget,
    );

    node.requestFocus();
    await tester.pumpAndSettle();
    final focused = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('spotlight-category-pill')),
    );
    final decoration = focused.decoration! as BoxDecoration;
    expect(decoration.color, IptvStyleTokens.spotlight.focusFill);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    expect(opened, 1);

    await tester.tap(
      find.byKey(const ValueKey<String>('spotlight-category-options')),
    );
    expect(options, 1);
    semantics.dispose();
  });

  testWidgets('rail exposes every group, count and callback', (tester) async {
    final favorites = _playlist('favorites', 'Favorites', 'favorites://all');
    final continuing = _playlist('continue', 'Continue', 'continue://watching');
    final custom = _playlist('iptv-list-news', 'News list', 'list://news');
    final source = _playlist(
      'source',
      'Family provider',
      'https://example.com/playlist.m3u',
    );
    final addon = _playlist('addon', 'Live addon', 'stremio-addon://live');
    final selected = <String>[];
    final actions = <String>[];

    await _pump(
      tester,
      SizedBox(
        width: 260,
        height: 740,
        child: SpotlightRail(
          playlists: [favorites, continuing, custom, source, addon],
          selectedPlaylist: source,
          sourceCounts: const {'source': 1260, 'addon': 7},
          customListCounts: const {'iptv-list-news': 18},
          favoritesCount: 12,
          continueWatchingCount: 4,
          recordingsCount: 2,
          onSelectPlaylist: (playlist) => selected.add(playlist.id),
          onOpenRecordings: () => actions.add('recordings'),
          onNewList: () => actions.add('new-list'),
          onAddPlaylist: () => actions.add('add-playlist'),
          onAddAddon: () => actions.add('add-addon'),
          onManageSources: () => actions.add('manage-sources'),
        ),
      ),
    );

    for (final heading in const [
      'QUICK ACCESS',
      'YOUR LISTS',
      'YOUR PLAYLISTS',
      'STREMIO ADDONS',
      'ACTIONS',
    ]) {
      expect(find.text(heading), findsOneWidget);
    }
    for (final label in const [
      'Favorites',
      'Continue Watching',
      'Recordings',
      'News list',
      'Family provider',
      'Live addon',
      'New list',
      'Add playlist',
      'Add addon',
      'Manage sources',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('1.3K'), findsOneWidget);

    Focus.of(tester.element(find.text('Family provider'))).requestFocus();
    await tester.pumpAndSettle();
    final focused = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey<String>('spotlight-rail-tile-playlist-source')),
    );
    expect(
      (focused.decoration! as BoxDecoration).color,
      IptvStyleTokens.spotlight.focusFill,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, ['source']);

    await tester.tap(find.text('Add playlist'));
    await tester.pump();
    expect(actions, ['add-playlist']);
  });

  testWidgets('rail DPAD down moves without selecting and OK selects', (
    tester,
  ) async {
    final firstNode = FocusNode(debugLabel: 'spotlight-first-rail-item');
    addTearDown(firstNode.dispose);
    final favorites = _playlist('favorites', 'Favorites', 'favorites://all');
    final continuing = _playlist('continue', 'Continue', 'continue://watching');
    final selected = <String>[];
    var upExits = 0;
    var rightExits = 0;

    await _pump(
      tester,
      SizedBox(
        width: 260,
        height: 600,
        child: SpotlightRail(
          playlists: [favorites, continuing],
          selectedPlaylist: favorites,
          sourceCounts: const {},
          favoritesCount: 1,
          recordingsCount: 0,
          showRecordings: false,
          firstItemFocusNode: firstNode,
          autofocusFirstItem: true,
          onUpFromFirstItem: () => upExits++,
          onExitRight: () => rightExits++,
          onSelectPlaylist: (playlist) => selected.add(playlist.id),
          onNewList: () {},
          onAddPlaylist: () {},
          onAddAddon: () {},
          onManageSources: () {},
        ),
      ),
    );

    await tester.pump();
    expect(firstNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(upExits, 1);
    expect(rightExits, 1);
    expect(firstNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(selected, isEmpty);
    expect(
      Focus.of(tester.element(find.text('Continue Watching'))).hasFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(selected, ['continue']);
  });

  testWidgets('content-type segments use existing values and DPAD activation', (
    tester,
  ) async {
    final liveNode = FocusNode(debugLabel: 'live-content-type');
    addTearDown(liveNode.dispose);
    final changes = <String>[];

    await _pump(
      tester,
      SizedBox(
        width: 420,
        child: SpotlightContentTypeControl(
          value: SpotlightContentTypeControl.live,
          firstItemFocusNode: liveNode,
          onChanged: changes.add,
        ),
      ),
    );

    expect(find.text('Live TV'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);

    liveNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(Focus.of(tester.element(find.text('Movies'))).hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(changes, [SpotlightContentTypeControl.movies]);
  });
}
