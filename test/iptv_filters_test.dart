import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/iptv_filters.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'classic category picker presents its secondary action as options',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final playlist = IptvPlaylist(
        id: 'provider',
        name: 'Provider',
        url: 'https://example.com/list.m3u',
        addedAt: DateTime(2026),
      );
      String? optionsCategory;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: IptvFiltersBar(
              playlists: [playlist],
              selectedPlaylist: playlist,
              categories: const ['Sports'],
              selectedCategory: null,
              channelCount: 1,
              isLoading: false,
              onPlaylistChanged: (_) {},
              onCategoryChanged: (_) {},
              onCategoryOptions: (category) => optionsCategory = category,
            ),
          ),
        ),
      );

      await tester.tap(find.text('All Categories'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Category options'), findsOneWidget);
      expect(
        find.text('Tap the menu (or long-press) for category options'),
        findsOneWidget,
      );
      expect(find.textContaining('Tap the eye'), findsNothing);

      await tester.tap(find.byTooltip('Category options'));
      await tester.pumpAndSettle();

      expect(optionsCategory, 'Sports');
    },
  );
}
