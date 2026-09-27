import '../../../models/play_loader_art.dart';
import '../../../models/stremio_addon.dart';

/// One mounted view's loader artwork. Detail enrichment and catalog quick-play
/// share this owner; unmatched selections receive no artwork instead of the
/// previous title's backdrop. It owns no timers, listeners or native resources.
class HomePlaybackArtwork {
  PlayLoaderArt? _art;
  String? _key;

  PlayLoaderArt? get current => _art;

  void capture(StremioMeta item) {
    final key = _identityKey(item.progressId ?? item.id, item.name);
    // A detail route can have supplied richer art for this exact title. Even
    // a sparse catalog refresh must not replace the already-adopted object.
    if (_art != null && _key == key) return;
    final art = PlayLoaderArt.fromMeta(item);
    if (art.isEmpty) {
      _art = null;
      _key = null;
      return;
    }
    _art = art;
    _key = key;
  }

  void adopt(StremioMeta item, PlayLoaderArt art) {
    _art = art;
    _key = _identityKey(item.progressId ?? item.id, item.name);
  }

  PlayLoaderArt? forSelection(String? id, String title) {
    final art = _art;
    if (art == null) return null;
    // Preserve exact normalized-key matching and the legacy non-empty ID
    // fallback: tracker selections often have differently punctuated titles.
    if (_identityKey(id, title) == _key) return art;
    final storedId = _key?.split('|').first ?? '';
    if (storedId.isNotEmpty && id == storedId) return art;
    return null;
  }

  static String _identityKey(String? id, String title) =>
      '${id ?? ''}|${title.trim().toLowerCase()}';
}
