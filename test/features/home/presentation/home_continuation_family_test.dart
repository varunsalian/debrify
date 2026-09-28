import 'package:debrify/features/home/presentation/home_stage_rows.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'merged family retains movie identity and series metadata without duplicate nodes',
    () {
      final movieNodes = [FocusNode()];
      final seriesNodes = [FocusNode()];
      addTearDown(() {
        movieNodes.single.dispose();
        seriesNodes.single.dispose();
      });
      const movie = StremioMeta(id: 'm', type: 'movie', name: 'Movie');
      const series = StremioMeta(id: 's', type: 'series', name: 'Series');
      var merged = false;
      var enabled = true;
      final disabled = <String>{};
      final opened = <StremioMeta>[];
      List<HomeContinuationRow> build() => buildHomeContinuationFamily(
        movieId: 'cw:movies',
        seriesId: 'cw:series',
        title: 'Continue',
        seriesTag: 'Series',
        kind: HomeContinuationKind.local,
        enabled: enabled,
        merged: merged,
        disabled: disabled,
        movieItems: merged ? [movie, series] : [movie],
        seriesItems: [series],
        movieNodes: movieNodes,
        seriesNodes: seriesNodes,
        progress: (_) => .5,
        episode: (_) => 'S1 E2',
        remaining: (_) => 10,
        artwork: (_) => 'episode-art',
        onOpen: opened.add,
        onQuickPlay: opened.add,
        onRemove: (_) async {},
        canRemove: (item) => item.id == 's',
      );
      final split = build();
      expect(split.map((row) => row.rowId), ['cw:movies', 'cw:series']);
      expect(split.first.episodeOf(movie), isNull);
      expect(split.first.episodeArtworkOf(movie), isNull);
      expect(split.last.episodeOf(series), 'S1 E2');
      expect(split.last.nodes, same(seriesNodes));
      merged = true;
      final combined = build().single;
      expect(combined.rowId, 'cw:movies');
      expect(combined.tag, isNull);
      expect(combined.nodes, same(movieNodes));
      expect(combined.items, [movie, series]);
      expect(combined.episodeArtworkOf(series), 'episode-art');
      expect(combined.canRemove!(series), isTrue);
      combined.onOpen(series);
      expect(opened, [series]);
      disabled.add('cw:movies');
      expect(build(), isEmpty);
      disabled.clear();
      enabled = false;
      expect(build(), isEmpty);
    },
  );
}
