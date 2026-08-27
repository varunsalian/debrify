import '../../core/cloud/listing.dart';
import 'models/file.dart';

/// One folder on the way down, so Back knows where it came from.
class PikPakCrumb {
  /// Null at the drive root.
  final String? id;
  final String name;

  const PikPakCrumb({required this.id, required this.name});
}

/// Everything the PikPak browser renders from.
///
/// Immutable, replaced wholesale through [copyWith]. What it deliberately does
/// NOT hold: focus nodes, scroll positions, text controllers. Those belong to
/// the widget, live and die with it, and would make this untestable.
class PikPakBrowseState {
  /// What the list shows right now — already filtered and ordered.
  final List<PikPakFile> files;

  /// A fetch is in flight and the list should show a spinner rather than an
  /// empty state.
  final bool isLoading;

  /// No successful load has happened yet, so "no files" means "not yet",
  /// not "this folder is empty".
  final bool initialLoad;

  /// Non-empty when the last load failed.
  final String error;

  final bool isLoadingMore;
  final bool hasMore;

  /// Root first; empty means the drive root.
  final List<PikPakCrumb> path;

  /// The folder a restricted profile is pinned to. Back stops here.
  final bool atRestrictedRoot;

  final bool showVideosOnly;
  final bool ignoreSmallVideos;

  /// Per folder id, so leaving and returning keeps the arrangement.
  final Map<String, CloudViewMode> viewModes;

  /// Non-null while inside a client-side season grouping, which is not a real
  /// PikPak folder and so is not on [path].
  final PikPakFile? virtualFolder;

  final bool selecting;
  final Set<String> selectedIds;

  final bool searching;
  final String query;
  final List<PikPakFile> results;

  const PikPakBrowseState({
    this.files = const [],
    this.isLoading = false,
    this.initialLoad = true,
    this.error = '',
    this.isLoadingMore = false,
    this.hasMore = true,
    this.path = const [],
    this.atRestrictedRoot = false,
    this.showVideosOnly = true,
    this.ignoreSmallVideos = true,
    this.viewModes = const {},
    this.virtualFolder,
    this.selecting = false,
    this.selectedIds = const {},
    this.searching = false,
    this.query = '',
    this.results = const [],
  });

  /// The folder being listed. Null at the drive root.
  String? get folderId => path.isEmpty ? null : path.last.id;

  String get folderName => path.isEmpty ? 'My Files' : path.last.name;

  bool get inVirtualFolder => virtualFolder != null;

  /// Back has somewhere to go.
  bool get canGoUp => inVirtualFolder || path.isNotEmpty;

  CloudViewMode get viewMode => viewModes[folderId ?? ''] ?? CloudViewMode.raw;

  /// What the list actually renders — the season grouping when inside one,
  /// search results while searching, the folder otherwise.
  List<PikPakFile> get visible {
    if (searching) return results;
    if (virtualFolder != null) return virtualFolder!.children;
    return files;
  }

  /// Entries the user can act on in bulk. A folder is not one of them: PikPak
  /// deletes a folder and its contents as one call, so mixing them into a
  /// multi-select would delete more than was ticked.
  Iterable<PikPakFile> get selectable => visible.where((f) => !f.isFolder);

  bool get allSelected =>
      selectable.isNotEmpty &&
      selectable.every((f) => selectedIds.contains(f.id));

  bool get isEmpty => !isLoading && !initialLoad && visible.isEmpty;

  PikPakBrowseState copyWith({
    List<PikPakFile>? files,
    bool? isLoading,
    bool? initialLoad,
    String? error,
    bool? isLoadingMore,
    bool? hasMore,
    List<PikPakCrumb>? path,
    bool? atRestrictedRoot,
    bool? showVideosOnly,
    bool? ignoreSmallVideos,
    Map<String, CloudViewMode>? viewModes,
    PikPakFile? virtualFolder,
    bool clearVirtualFolder = false,
    bool? selecting,
    Set<String>? selectedIds,
    bool? searching,
    String? query,
    List<PikPakFile>? results,
  }) => PikPakBrowseState(
    files: files ?? this.files,
    isLoading: isLoading ?? this.isLoading,
    initialLoad: initialLoad ?? this.initialLoad,
    error: error ?? this.error,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore: hasMore ?? this.hasMore,
    path: path ?? this.path,
    atRestrictedRoot: atRestrictedRoot ?? this.atRestrictedRoot,
    showVideosOnly: showVideosOnly ?? this.showVideosOnly,
    ignoreSmallVideos: ignoreSmallVideos ?? this.ignoreSmallVideos,
    viewModes: viewModes ?? this.viewModes,
    virtualFolder: clearVirtualFolder
        ? null
        : (virtualFolder ?? this.virtualFolder),
    selecting: selecting ?? this.selecting,
    selectedIds: selectedIds ?? this.selectedIds,
    searching: searching ?? this.searching,
    query: query ?? this.query,
    results: results ?? this.results,
  );

  @override
  String toString() =>
      'PikPakBrowse(${visible.length} shown, ${path.length} deep'
      '${isLoading ? ', loading' : ''}'
      '${error.isEmpty ? '' : ', error'}'
      '${selecting ? ', ${selectedIds.length} selected' : ''}'
      '${searching ? ', searching' : ''})';
}

/// The one-shot things the browser asks its view to do.
sealed class PikPakBrowseEffect {
  const PikPakBrowseEffect();
}

/// Tell the user something. [isError] picks the styling, not the wording.
final class PikPakNotify extends PikPakBrowseEffect {
  final String message;
  final bool isError;
  const PikPakNotify(this.message, {this.isError = false});
}

/// The folder a restricted profile was pinned to is gone. The view has to sign
/// the user out and leave — continuing would show them the whole drive.
final class PikPakRestrictedFolderLost extends PikPakBrowseEffect {
  const PikPakRestrictedFolderLost();
}

/// A load finished and the list changed identity, so a television should put
/// focus back on the first row rather than leaving it on a row that is gone.
final class PikPakFocusFirstItem extends PikPakBrowseEffect {
  const PikPakFocusFirstItem();
}
