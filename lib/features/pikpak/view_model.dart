import '../../core/cloud/listing.dart';
import '../../core/view_model.dart';
import 'view_state.dart';
import 'data/repository.dart';
import 'models/file.dart';
import 'listing.dart';

/// Whether a delete removes a file for good or moves it to PikPak's trash.
typedef PikPakTrashPreference = Future<bool> Function();

/// The season a filename belongs to, or null when it names none.
///
/// Injected because the parser that actually does this well — `SeriesParser`,
/// which reads S01E01, 1x01, and the dozen other spellings — imports
/// `flutter/foundation`, and domain does not take a Flutter dependency to
/// borrow a regex. [seasonNumberIn] is the naive fallback and is only right
/// for folder names.
typedef SeasonOf = int? Function(String filename);

/// The PikPak file browser, without the widget.
///
/// Everything `_PikPakFilesScreenState` did to *decide* what to show —
/// listing, paging, walking in and out of folders, filtering, ordering,
/// multi-select, search, delete — lives here and is reachable from a plain
/// `test()`. What stayed in the widget is what the framework owns: focus
/// nodes, scroll controllers, text controllers.
///
/// Dependencies arrive through the constructor. [drive] is a port, so a test
/// hands it a fake and nothing opens a socket.
final class PikPakBrowseViewModel
    extends ViewModel<PikPakBrowseState, PikPakBrowseEffect> {
  final PikPakRepository _drive;

  /// The folder a restricted profile is pinned to, or null when unrestricted.
  /// Back stops here and the browser never lists above it.
  final String? _restrictedRootId;

  /// Read at delete time rather than cached: the user can change it in
  /// Settings while the browser is open.
  final PikPakTrashPreference _preferTrash;
  final SeasonOf _seasonOf;

  String? _nextPageToken;

  /// Guards against a stale page landing after the user has moved on. Each
  /// load takes the next value; a response whose token no longer matches is
  /// dropped rather than appended to the wrong folder.
  int _loadToken = 0;

  PikPakBrowseViewModel({
    required PikPakRepository drive,
    required PikPakTrashPreference preferTrash,
    required SeasonOf seasonOf,
    String? restrictedRootId,
    String? restrictedRootName,
  }) : _drive = drive,
       _preferTrash = preferTrash,
       _seasonOf = seasonOf,
       _restrictedRootId = restrictedRootId,
       super(
         PikPakBrowseState(
           path: restrictedRootId == null
               ? const []
               : [
                   PikPakCrumb(
                     id: restrictedRootId,
                     name: restrictedRootName ?? 'My Files',
                   ),
                 ],
           atRestrictedRoot: restrictedRootId != null,
         ),
       );

  // ── loading ────────────────────────────────────────────────────────────

  /// Replace the current folder's contents.
  Future<void> load({
    bool showVideosOnly = true,
    bool ignoreSmallVideos = true,
  }) async {
    final token = ++_loadToken;

    emit(
      state.copyWith(
        isLoading: true,
        error: '',
        hasMore: true,
        showVideosOnly: showVideosOnly,
        ignoreSmallVideos: ignoreSmallVideos,
      ),
    );
    _nextPageToken = null;

    try {
      final result = await _drive.listFiles(parentId: state.folderId);
      if (token != _loadToken) return;

      _nextPageToken = result.nextPageToken;
      emit(
        state.copyWith(
          files: _arrange(_filter(result.files)),
          hasMore: _hasNextPage,
          isLoading: false,
          initialLoad: false,
          error: '',
        ),
      );
      effect(const PikPakFocusFirstItem());
    } catch (e) {
      if (token != _loadToken) return;

      // A restricted profile whose pinned folder was deleted out from under it
      // gets an error here rather than an empty listing. Showing the drive root
      // instead would hand it the whole account.
      if (_restrictedRootId != null && state.folderId == _restrictedRootId) {
        if (!await _drive.verifyRestrictedFolderExists()) {
          effect(const PikPakRestrictedFolderLost());
          return;
        }
      }

      emit(state.copyWith(error: '$e', isLoading: false, initialLoad: false));
    }
  }

  /// Append the next page. No-op when one is already in flight or the folder
  /// has no more.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || _nextPageToken == null) return;
    final token = _loadToken;

    emit(state.copyWith(isLoadingMore: true));
    try {
      final result = await _drive.listFiles(
        parentId: state.folderId,
        pageToken: _nextPageToken,
      );
      if (token != _loadToken) return;

      _nextPageToken = result.nextPageToken;
      emit(
        state.copyWith(
          files: _arrange([...state.files, ..._filter(result.files)]),
          hasMore: _hasNextPage,
          isLoadingMore: false,
        ),
      );
    } catch (e) {
      if (token != _loadToken) return;
      emit(state.copyWith(isLoadingMore: false));
      effect(PikPakNotify('Failed to load more files: $e', isError: true));
    }
  }

  Future<void> refresh() {
    _clearSelection();
    return load(
      showVideosOnly: state.showVideosOnly,
      ignoreSmallVideos: state.ignoreSmallVideos,
    );
  }

  bool get _hasNextPage => _nextPageToken != null && _nextPageToken!.isNotEmpty;

  List<PikPakFile> _filter(List<PikPakFile> files) => pikpakListing.filter(
    files,
    videosOnly: state.showVideosOnly,
    minVideoBytes: state.ignoreSmallVideos ? pikpakMinVideoBytes : 0,
  );

  List<PikPakFile> _arrange(List<PikPakFile> files) => switch (state.viewMode) {
    CloudViewMode.raw => files,
    CloudViewMode.sortedAZ => pikpakListing.sorted(files),
    // Season grouping is applied by [setViewMode], which needs the whole
    // folder rather than a page of it.
    CloudViewMode.seriesArrange => files,
  };

  // ── navigation ─────────────────────────────────────────────────────────

  Future<void> openFolder(PikPakFile folder) {
    _clearSelection();
    emit(
      state.copyWith(
        path: [
          ...state.path,
          PikPakCrumb(id: folder.id, name: folder.name),
        ],
        atRestrictedRoot: false,
        files: const [],
        searching: false,
        query: '',
        results: const [],
        clearVirtualFolder: true,
      ),
    );
    return load(
      showVideosOnly: state.showVideosOnly,
      ignoreSmallVideos: state.ignoreSmallVideos,
    );
  }

  /// Step into a client-side season grouping. No fetch: its contents are
  /// already in hand.
  void openVirtualFolder(PikPakFile group) {
    if (!group.isVirtual) return;
    _clearSelection();
    emit(state.copyWith(virtualFolder: group));
  }

  /// Back. Returns false when there is nowhere left to go, which is the view's
  /// signal to pop the route instead.
  Future<bool> goUp() async {
    if (state.inVirtualFolder) {
      _clearSelection();
      emit(state.copyWith(clearVirtualFolder: true));
      return true;
    }
    if (state.path.length <= (_restrictedRootId == null ? 0 : 1)) return false;

    _clearSelection();
    final path = state.path.sublist(0, state.path.length - 1);
    emit(
      state.copyWith(
        path: path,
        atRestrictedRoot: _restrictedRootId != null && path.length == 1,
        files: const [],
      ),
    );
    await load(
      showVideosOnly: state.showVideosOnly,
      ignoreSmallVideos: state.ignoreSmallVideos,
    );
    return true;
  }

  // ── view mode ──────────────────────────────────────────────────────────

  /// Season grouping needs every file in the folder, not the page that
  /// happens to be loaded, so it fetches recursively before arranging.
  Future<void> setViewMode(CloudViewMode mode) async {
    final key = state.folderId ?? '';
    emit(state.copyWith(viewModes: {...state.viewModes, key: mode}));

    if (mode != CloudViewMode.seriesArrange) {
      emit(state.copyWith(files: _arrange(state.files)));
      return;
    }

    final folderId = state.folderId;
    if (folderId == null) {
      emit(
        state.copyWith(
          files: groupIntoSeasons(state.files, seasonOf: _seasonOf),
        ),
      );
      return;
    }

    final token = ++_loadToken;
    emit(state.copyWith(isLoading: true));
    try {
      final all = await _drive.listFilesRecursive(
        folderId: folderId,
        includePaths: true,
      );
      if (token != _loadToken) return;
      emit(
        state.copyWith(
          files: groupIntoSeasons(_filter(all), seasonOf: _seasonOf),
          isLoading: false,
        ),
      );
    } catch (e) {
      if (token != _loadToken) return;
      emit(
        state.copyWith(
          files: pikpakListing.sorted(state.files),
          viewModes: {...state.viewModes, key: CloudViewMode.sortedAZ},
          isLoading: false,
        ),
      );
      effect(PikPakNotify('Could not arrange as a series, sorted instead: $e'));
    }
  }

  // ── selection ──────────────────────────────────────────────────────────

  void toggleSelecting() =>
      emit(state.copyWith(selecting: !state.selecting, selectedIds: const {}));

  void toggleSelected(String id) {
    final next = Set<String>.from(state.selectedIds);
    next.contains(id) ? next.remove(id) : next.add(id);
    emit(state.copyWith(selectedIds: next));
  }

  void toggleSelectAll() => emit(
    state.copyWith(
      selectedIds: state.allSelected
          ? const {}
          : state.selectable.map((f) => f.id).toSet(),
    ),
  );

  void _clearSelection() {
    if (state.selecting || state.selectedIds.isNotEmpty) {
      emit(state.copyWith(selecting: false, selectedIds: const {}));
    }
  }

  // ── delete ─────────────────────────────────────────────────────────────

  /// Remove [ids], honouring the user's trash-vs-delete preference. The view
  /// is responsible for having asked first.
  Future<void> delete(List<String> ids) async {
    if (ids.isEmpty) return;
    final toTrash = await _preferTrash();
    try {
      final ok = toTrash
          ? await _drive.batchTrashFiles(ids)
          : await _drive.batchDeleteFiles(ids);
      if (!ok) {
        effect(const PikPakNotify('PikPak refused the delete.', isError: true));
        return;
      }
      effect(
        PikPakNotify(
          ids.length == 1
              ? (toTrash ? 'Moved to trash' : 'Deleted')
              : (toTrash
                    ? 'Moved ${ids.length} items to trash'
                    : 'Deleted ${ids.length} items'),
        ),
      );
      await refresh();
    } catch (e) {
      effect(PikPakNotify('Delete failed: $e', isError: true));
    }
  }

  // ── search ─────────────────────────────────────────────────────────────

  void openSearch() => emit(state.copyWith(searching: true));

  void closeSearch() =>
      emit(state.copyWith(searching: false, query: '', results: const []));

  /// Search the whole subtree, not just the loaded page — the file the user
  /// is looking for is usually inside a season folder.
  Future<void> search(String query) async {
    final trimmed = query.trim();
    emit(state.copyWith(query: trimmed));
    if (trimmed.isEmpty) {
      emit(state.copyWith(results: const []));
      return;
    }

    final folderId = state.folderId;
    final token = ++_loadToken;
    emit(state.copyWith(isLoading: true));
    try {
      final pool = folderId == null
          ? state.files
          : await _drive.listFilesRecursive(
              folderId: folderId,
              includePaths: true,
            );
      if (token != _loadToken) return;
      emit(
        state.copyWith(
          results: pikpakListing.search(_filter(pool), trimmed),
          isLoading: false,
        ),
      );
    } catch (e) {
      if (token != _loadToken) return;
      emit(state.copyWith(isLoading: false));
      effect(PikPakNotify('Search failed: $e', isError: true));
    }
  }

  // ── filters ────────────────────────────────────────────────────────────

  Future<void> setFilters({
    required bool showVideosOnly,
    required bool ignoreSmallVideos,
  }) {
    emit(
      state.copyWith(
        showVideosOnly: showVideosOnly,
        ignoreSmallVideos: ignoreSmallVideos,
      ),
    );
    return load(
      showVideosOnly: showVideosOnly,
      ignoreSmallVideos: ignoreSmallVideos,
    );
  }
}

/// Gather loose episodes into per-season folders, leaving real folders and
/// non-video files where they are.
///
/// Top level, not a method, because it is a pure function of the listing and
/// the other providers will want it once they adopt [CloudListing].
List<PikPakFile> groupIntoSeasons(
  List<PikPakFile> items, {
  required SeasonOf seasonOf,
}) {
  final (:folders, :videos, :others) = pikpakListing.partition(items);
  if (videos.isEmpty) return items;

  final resolve = seasonOf;
  final bySeason = <int, List<PikPakFile>>{};
  for (final video in videos) {
    // Anything that does not name a season is still a season 1 episode as far
    // as the browser is concerned — leaving it out would hide it entirely.
    bySeason.putIfAbsent(resolve(video.name) ?? 1, () => []).add(video);
  }

  final seasons = bySeason.keys.toList()..sort();
  return [
    ...folders,
    for (final season in seasons)
      PikPakFile.seasonGroup(season: season, files: bySeason[season]!),
    ...others,
  ];
}
