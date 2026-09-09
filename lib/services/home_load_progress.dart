import 'dart:async';

import '../models/stremio_addon.dart';
import 'home_collection_rows.dart';
import 'home_list_rows.dart';
import 'home_row_order.dart';

/// A timed-out initial batch may have published only its later catalogs.
/// Retrying from the safe cursor must fill earlier slots, not duplicate known
/// rows or turn completion order into the user's catalog order.
List<CatalogSection> mergeHomeCatalogRows({
  required List<CatalogSection> previous,
  required List<CatalogSection> additions,
  required List<String> catalogOrder,
  required String Function(CatalogSection) rowId,
}) {
  bool extra(CatalogSection row) =>
      row is HomeCollectionSection || row is HomeListSection;
  final catalogs = <String, CatalogSection>{
    for (final row in additions) rowId(row): row,
    // Already visible rows own any horizontal pages loaded in the meantime.
    for (final row in previous.where((row) => !extra(row))) rowId(row): row,
  };
  return [
    ...previous.where(extra),
    ...HomeRowOrder.apply(catalogs.values.toList(), catalogOrder, rowId),
  ];
}

/// One load's partial results. Arrival order never becomes catalog order, and
/// neither a late completion nor a queued publication may cross a generation
/// or profile boundary. Existing row objects retain horizontal paging state.
class HomeLoadProgress {
  HomeLoadProgress({
    required this.isCurrent,
    required this.rowId,
    required this.onPublish,
  });

  final bool Function() isCurrent;
  final String Function(CatalogSection) rowId;
  final void Function(List<CatalogSection> rows, bool first) onPublish;
  List<HomeCollectionSection> _collections = const [];
  List<HomeListSection> _lists = const [];
  List<String> _order = const [];
  final Map<String, CatalogSection> _catalogs = {};
  Timer? _publication;
  bool _closed = false;
  bool hasPublished = false;
  List<CatalogSection> _published = const [];

  void collections(List<HomeCollectionSection> rows) {
    if (_closed || !isCurrent()) return;
    _collections = rows;
    _schedule();
  }

  void catalogOrder(List<String> ids) => _order = List.of(ids);

  void lists(List<HomeListSection> rows) {
    if (_closed || !isCurrent()) return;
    _lists = rows;
    _schedule();
  }

  void catalog(CatalogSection row) {
    if (_closed || !isCurrent()) return;
    _catalogs[rowId(row)] = row;
    _schedule();
  }

  void _schedule() {
    if (!hasPublished) {
      flush();
    } else {
      // Coalesce same-burst arrivals without waiting for a slow sibling.
      _publication ??= Timer(const Duration(milliseconds: 32), flush);
    }
  }

  void flush({bool allowEmpty = false}) {
    _publication?.cancel();
    _publication = null;
    if (_closed || !isCurrent()) return;
    final rows = <CatalogSection>[
      ..._collections.where((row) => row.collection.pinToTop),
      ..._lists,
      ..._collections.where((row) => !row.collection.pinToTop),
      for (final id in _order)
        if (_catalogs[id] case final row?) row,
    ];
    if (rows.isEmpty && !allowEmpty) return;
    if (hasPublished &&
        rows.length == _published.length &&
        Iterable<int>.generate(
          rows.length,
        ).every((i) => identical(rows[i], _published[i]))) {
      return;
    }
    final first = !hasPublished;
    hasPublished = true;
    _published = List.unmodifiable(rows);
    onPublish(_published, first);
  }

  void dispose() {
    _closed = true;
    _publication?.cancel();
    _publication = null;
  }
}
