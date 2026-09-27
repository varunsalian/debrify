import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'home_row_entrance.dart';

/// Lazy Classic rows. Home uses stable row IDs; catalog search keeps index keys.
class HomeClassicRows extends StatelessWidget {
  HomeClassicRows({
    super.key,
    required this.scrollController,
    required this.generation,
    required this.catalogRowCount,
    required List<String>? orderedRowIds,
    required this.rowBuilder,
    required this.footerBuilder,
    required this.showFooter,
    required this.tailPadding,
    required this.isFresh,
  }) : orderedRowIds = orderedRowIds == null
           ? null
           : List.unmodifiable(orderedRowIds);

  final ScrollController scrollController;
  final int generation;
  final int catalogRowCount;
  final List<String>? orderedRowIds;
  final IndexedWidgetBuilder rowBuilder;
  final WidgetBuilder footerBuilder;
  final bool showFooter;
  final double tailPadding;
  final bool Function() isFresh;

  @override
  Widget build(BuildContext context) {
    final ids = orderedRowIds;
    final prefix = 'board-reveal-$generation-';
    final indices = <String, int>{
      if (ids != null)
        for (var i = 0; i < ids.length; i++) ids[i]: i,
    };
    int? findIndex(Key key) {
      if (key is! ValueKey<String> || !key.value.startsWith(prefix)) {
        return null;
      }
      return indices[key.value.substring(prefix.length)];
    }

    final count = ids?.length ?? catalogRowCount;
    return ListView.builder(
      controller: scrollController,
      // Preserve mounted row state/focus when tracker or CW rows arrive above it.
      findChildIndexCallback: ids == null ? null : findIndex,
      padding: EdgeInsets.only(top: 6, bottom: 32 + tailPadding),
      // Keep the original ~1.5 rows of pre-build on weak TV chips.
      scrollCacheExtent: const ScrollCacheExtent.pixels(300),
      itemCount: count + (showFooter ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= count) return footerBuilder(context);
        final row = rowBuilder(context, index);
        final identity = ids == null ? 'index:$index' : ids[index];
        // Evaluate at lazy materialization time, after constructing the row.
        final fresh = isFresh();
        return HomeRowEntrance(
          key: ValueKey('$prefix$identity'),
          play: fresh && index < 6,
          delayMs: 60 * index,
          child: row,
        );
      },
    );
  }
}
