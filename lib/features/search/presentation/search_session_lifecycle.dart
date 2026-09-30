import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart'
    show ProfileSessionOwner;
import '../../../utils/tv_search_focus_handoff.dart';
import '../models/search_session.dart';
import '../application/keyword_snapshot_dependencies.dart';
import '../data/keyword_snapshot_repository.dart';
import '../models/keyword_snapshot.dart';
import '../models/keyword_cache_state.dart';
import '../../home/presentation/home_board_rows.dart';
import '../../home/presentation/home_board_paging.dart';
import 'search_result_bindings.dart';
import 'keyword_search_section.dart';
import 'keyword_return.dart';

typedef SearchSessionLifecycleDeps = ({
  bool Function() mounted,
  bool Function() isTelevision,
  void Function(VoidCallback) setState,
});

/// Owns this view's captured profile, retained keyword repository and Search bindings.
class SearchSessionLifecycle {
  SearchSessionLifecycle(
    this.ref,
    this._deps,
    this._keywordSection,
    this._keywordReturn,
    this._rows,
    this._paging,
    this._searchSubmitFocus,
  );
  final WidgetRef ref;
  final SearchSessionLifecycleDeps _deps;
  final KeywordSearchSection _keywordSection;
  final KeywordReturn _keywordReturn;
  final HomeBoardRows _rows;
  final HomeBoardPaging _paging;
  final TvSearchFocusHandoff _searchSubmitFocus;

  // Dedicated MDBList list-search state. Lists is its own Search mode; it
  // never runs as part of Catalog search. Each result card hands off via
  // MainPageBridge.pendingMdblistListOpen. One focus node per card.
  late final SearchSession searchSession;
  late final SearchResultBindings searchResultBindings;

  // Retain the plain snapshot adapter: disposal must not resolve WidgetRef.
  late final KeywordSnapshotRepository keywordSnapshots;

  /// Captured at mount, not dispose: an outgoing screen may be torn down after
  /// the next profile is published and must still tag its snapshot as outgoing.
  late final ProfileSessionOwner profileSessionOwner;

  KeywordSnapshot? initializeKeyword() {
    keywordSnapshots = ref.read(
      keywordSnapshotRepositoryProvider(profileSessionOwner),
    );
    final keywordSnapshot = _keywordReturn.take();
    searchSession = SearchSession(
      owner: profileSessionOwner,
      viewIdentity: Object(),
      initialKeywordQuery: keywordSnapshot?.query ?? '',
      initialKeywordResults: keywordSnapshot?.projection,
      initialKeywordCache:
          keywordSnapshot?.cache ?? const KeywordCacheState.empty(),
    );
    _keywordSection.startAppearance();
    unawaited(_keywordSection.loadSourceTextFormatting());
    // Retain state for this screen's mounted lifetime, including covered routes.
    // Returning from a pushed list must not discard results or replay a request.
    searchResultBindings = SearchResultBindings(
      ref,
      searchSession,
      isCurrent: _deps.mounted,
      isTelevision: _deps.isTelevision,
      onChanged: () => _deps.setState(() {}),
      replaceRows: _rows.applySections,
      appendRows: _paging.appendSections,
      presentKeyword: _keywordSection.presentKwStreaming,
      finishKeyword: _keywordSection.finishKeyword,
      cancelSubmitFocus: _searchSubmitFocus.cancel,
    );
    return keywordSnapshot;
  }
}
