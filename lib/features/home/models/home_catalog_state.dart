import 'home_board_configuration.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/home_load_deadline.dart';
import 'home_catalog_plan.dart';

typedef HomeCatalogSnapshot =
    HomeBoardSnapshot<HomeCatalogReference, StremioAddon>;

/// Inventory and reserved cursor are distinct from the last accepted board.
/// Containers are immutable; legacy addon/catalog identities are borrowed.
class HomeCatalogState {
  const HomeCatalogState.empty()
    : references = const [],
      cursor = 0,
      committed = null,
      refreshing = false,
      loadingMore = false,
      configuration = const HomeBoardConfiguration.empty();

  const HomeCatalogState._(
    this.references,
    this.cursor,
    this.committed,
    this.refreshing,
    this.loadingMore,
    this.configuration,
  );

  final List<HomeCatalogReference> references;
  final int cursor;
  final HomeCatalogSnapshot? committed;
  final bool refreshing;
  final bool loadingMore;
  final HomeBoardConfiguration configuration;

  bool get hasMore => cursor < references.length;

  HomeCatalogState copyWith({
    List<HomeCatalogReference>? references,
    int? cursor,
    HomeCatalogSnapshot? committed,
    bool? refreshing,
    bool? loadingMore,
    HomeBoardConfiguration? configuration,
  }) => HomeCatalogState._(
    references == null ? this.references : List.unmodifiable(references),
    cursor ?? this.cursor,
    committed ?? this.committed,
    refreshing ?? this.refreshing,
    loadingMore ?? this.loadingMore,
    configuration ?? this.configuration,
  );
}
