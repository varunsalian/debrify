import 'package:debrify/features/home/presentation/home_art_poster.dart';
import 'package:debrify/features/home/presentation/home_classic_favorite_rows.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'lazy IPTV cards capture the rendered item and clear VOD preview',
    (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      final old = IptvChannel(name: 'Old', url: 'https://example.invalid/old');
      final vod = IptvChannel(
        name: 'VOD',
        url: 'https://example.invalid/vod',
        contentType: 'vod',
      );
      var current = old;
      var showTitle = true;
      IptvChannel? opened;
      var cleared = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final rows = HomeClassicFavoriteRows(
                  context: context,
                  isTelevision: true,
                  posterWidth: 100,
                  captionBand: 30,
                  showTitle: () => showTitle,
                  nodes: () => [node],
                  up: (_) => () {},
                  down: (_) => () {},
                  sidebar: () {},
                  clearLive: () => cleared++,
                  previewLive: (_) => fail('VOD must not preview'),
                );
                final row = rows.iptv(
                  title: 'List',
                  customList: true,
                  count: 1,
                  itemAt: (_) => current,
                  onOpen: (item) => opened = item,
                );
                current = vod;
                showTitle = false;
                return row;
              },
            ),
          ),
        ),
      );
      final poster = tester.widget<HomeArtPoster>(find.byType(HomeArtPoster));
      expect(poster.title, 'VOD');
      expect(poster.showTitle, isFalse);
      current = old;
      poster.onOpen();
      expect(opened, same(vod));
      node.requestFocus();
      await tester.pump();
      expect(cleared, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
