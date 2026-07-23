import '../../models/stremio_addon.dart';
import 'mdblist_item_transformer.dart';
import 'mdblist_service.dart';

/// A selectable MDBList list. Value-equal by its numeric id so a dropdown can
/// match the current selection across rebuilds.
class MdblistListChoice {
  final int id;
  final String name;
  final int itemCount;
  final String? mediatype;

  const MdblistListChoice({
    required this.id,
    required this.name,
    this.itemCount = 0,
    this.mediatype,
  });

  factory MdblistListChoice.fromJson(Map<String, dynamic> j) {
    final rawName = j['name'] as String?;
    return MdblistListChoice(
      id: (j['id'] as num?)?.toInt() ?? -1,
      name: (rawName == null || rawName.trim().isEmpty)
          ? 'Untitled list'
          : rawName,
      itemCount: (j['items'] as num?)?.toInt() ?? 0,
      mediatype: j['mediatype'] as String?,
    );
  }

  String get label => name;

  @override
  bool operator ==(Object other) =>
      other is MdblistListChoice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Loads MDBList lists into [StremioMeta] grids for the Discover / See-All view.
/// Pure data logic — no UI — so it can be shared by any screen that browses
/// MDBList lists. Stateless singleton, mirroring [TraktListSource].
///
/// Step 2 scope: the user's OWN lists only. Top/public lists and list search
/// are a later step (see project memory).
class MdblistListSource {
  MdblistListSource._();
  static final MdblistListSource instance = MdblistListSource._();

  /// The user's own lists, ready to populate the "List" dropdown. Skips lists
  /// without a usable id. Returns [] when MDBList isn't connected or on error.
  Future<List<MdblistListChoice>> loadUserLists() async {
    final raw = await MdblistService.instance.fetchUserLists();
    final out = <MdblistListChoice>[];
    for (final j in raw) {
      final choice = MdblistListChoice.fromJson(j);
      if (choice.id >= 0) out.add(choice);
    }
    return out;
  }

  /// Load a list's items (movies + shows merged, deduped) + whether the fetch
  /// failed. A genuinely empty list returns `(items: [], failed: false)`; only a
  /// network/parse failure sets `failed: true`, so the UI can tell "empty" from
  /// "couldn't load".
  Future<({List<StremioMeta> items, bool failed})> loadListItems(
    MdblistListChoice choice,
  ) async {
    final data = await MdblistService.instance.fetchListItems(choice.id);
    if (data == null) return (items: const <StremioMeta>[], failed: true);
    final movies = data['movies'];
    final shows = data['shows'];
    final metas = <StremioMeta>[
      if (movies is List) ...MdblistItemTransformer.transformItems(movies),
      if (shows is List) ...MdblistItemTransformer.transformItems(shows),
    ];
    return (items: _dedup(metas), failed: false);
  }

  List<StremioMeta> _dedup(List<StremioMeta> metas) {
    final seen = <String>{};
    final out = <StremioMeta>[];
    for (final m in metas) {
      if (seen.add(m.imdbId ?? m.id)) out.add(m);
    }
    return out;
  }
}
