import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/torrent.dart';
import '../application/catalog_search_controller.dart';
import '../application/keyword_cache_controller.dart';
import '../application/keyword_results_controller.dart';
import '../application/keyword_search_controller.dart';
import '../application/lists_search_controller.dart';
import '../models/catalog_search_state.dart';
import '../models/keyword_cache_state.dart';
import '../models/keyword_results_state.dart';
import '../models/keyword_search_state.dart';
import '../models/lists_search_state.dart';
import '../models/search_session.dart';
import 'catalog_search_projection.dart';

/// Retains mounted Search result providers and forwards accepted publications
/// into existing presentation actions. It does not own requests or copied state.
class SearchResultBindings {
  SearchResultBindings(
    WidgetRef ref,
    SearchSession session, {
    required bool Function() isCurrent,
    required bool Function() isTelevision,
    required void Function() onChanged,
    required void Function(List<CatalogSection>) replaceRows,
    required void Function(List<CatalogSection>) appendRows,
    required void Function(List<Torrent>, int) presentKeyword,
    required void Function(int) finishKeyword,
    required void Function() cancelSubmitFocus,
  }) {
    void changed() {
      if (isCurrent()) onChanged();
    }

    _lists = ref.listenManual(
      listsSearchProvider(session),
      (_, _) => changed(),
    );
    _catalog = ref.listenManual(catalogSearchProvider(session), (
      previous,
      next,
    ) {
      if (!isCurrent()) return;
      if (!isTelevision() &&
          next.rows.isNotEmpty &&
          !identical(previous?.rows, next.rows)) {
        final previousCount = previous?.rows.length ?? 0;
        final additions = next.rows
            .skip(previousCount)
            .map(catalogSearchSection)
            .toList();
        if (previousCount == 0) {
          replaceRows(additions);
        } else {
          appendRows(additions);
        }
      } else {
        onChanged();
      }
    });
    // Cache badges repaint without recreating nodes or recomputing cached-only rows.
    _cache = ref.listenManual(
      keywordCacheProvider(session),
      (_, _) => changed(),
    );
    _results = ref.listenManual(
      keywordResultsProvider(session),
      (_, _) => changed(),
    );
    _search = ref.listenManual(keywordSearchProvider(session), (_, next) {
      if (!isCurrent()) return;
      final results = next.results;
      if (results != null) presentKeyword(results, next.request);
      if (next.status == KeywordSearchStatus.complete) {
        finishKeyword(next.request);
      } else if (next.status == KeywordSearchStatus.failed) {
        cancelSubmitFocus();
      }
      onChanged();
    });
  }

  late final ProviderSubscription<ListsSearchState> _lists;
  late final ProviderSubscription<CatalogSearchState> _catalog;
  late final ProviderSubscription<KeywordCacheState> _cache;
  late final ProviderSubscription<KeywordResultsState> _results;
  late final ProviderSubscription<KeywordSearchState> _search;
  ListsSearchState get lists => _lists.read();
  CatalogSearchState get catalog => _catalog.read();
  KeywordCacheState get cache => _cache.read();
  KeywordResultsState get results => _results.read();
  KeywordSearchState get search => _search.read();

  // The route closes its appearance subscription between these two phases.
  void closeCatalogAndLists() {
    _lists.close();
    _catalog.close();
  }

  void closeKeyword() {
    _results.close();
    _search.close();
    _cache.close();
  }
}
