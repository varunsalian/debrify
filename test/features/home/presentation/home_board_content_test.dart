import 'package:debrify/features/home/presentation/home_board_content.dart';
import 'package:debrify/widgets/skeleton_poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loading, empty and Search gates keep Home layout builders lazy', () {
    final built = <String>[];
    var spotlightReads = 0;
    Widget result(String name) {
      built.add(name);
      return Text(name);
    }

    Widget view({
      bool loading = false,
      String? error,
      bool empty = false,
      bool reserving = false,
      bool search = false,
      bool tv = true,
      String style = 'canvas',
      bool shelves = true,
    }) => buildHomeBoardContent(
      loading: loading,
      isTelevision: tv,
      error: error,
      continuationVisible: false,
      catalogsEmpty: empty,
      favoritesVisible: false,
      traktReserving: reserving,
      query: '',
      searchFailures: 0,
      searchMode: search,
      style: style,
      spotlightHasContent: () {
        spotlightReads++;
        return shelves;
      },
      layouts: {
        for (final name in ['canvas', 'spotlight']) name: () => result(name),
      },
      searchSpotlight: () => result('search'),
      classic: () => result('classic'),
      onRetry: () {},
      message: (_, title, body, {onRetry}) => result(title),
    );
    expect(view(loading: true), isA<BrandLoadingStage>());
    expect(built, isEmpty);
    view(error: 'failure');
    expect(built.removeLast(), "Couldn't load catalogs");
    view(empty: true);
    expect(built.removeLast(), 'No catalogs yet');
    view(empty: true, reserving: true);
    expect(built.removeLast(), 'canvas');
    view(search: true);
    expect(built.removeLast(), 'search');
    expect(spotlightReads, 0);
    view(style: 'spotlight', shelves: false);
    expect(built.removeLast(), 'classic');
    view(style: 'spotlight');
    expect(built.removeLast(), 'spotlight');
    expect(spotlightReads, 2);
    view(style: 'unknown');
    expect(built.removeLast(), 'classic');
    view(search: true, tv: false);
    expect(built.removeLast(), 'canvas');
  });
}
