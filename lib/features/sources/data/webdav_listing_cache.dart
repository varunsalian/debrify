import '../../../models/webdav_item.dart';

/// Short-lived memory cache of WebDAV folder listings, so moving between
/// episodes or reopening Sources does not list the same folders again.
///
/// Keys carry the server's identity and access revision, never its password.
/// A hit does not skip authorization: callers recheck access first.
final class WebDavListingCache {
  WebDavListingCache({
    this.ttl = const Duration(minutes: 5),
    this.maxEntries = 300,
    this.maxItems = 60000,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;

  /// Bounds memory when a server has a few enormous folders.
  final int maxItems;
  final DateTime Function() _clock;
  final _entries = <String, _CachedListing>{}; // Insertion-ordered.
  int _items = 0;

  List<WebDavItem>? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    if (_clock().difference(entry.storedAt) > ttl) {
      _items -= entry.items.length;
      return null;
    }
    _entries[key] = entry; // Most recently used last.
    return entry.items;
  }

  void put(String key, List<WebDavItem> items) {
    if (items.length > maxItems) return;
    final previous = _entries.remove(key);
    if (previous != null) _items -= previous.items.length;
    _entries[key] = _CachedListing(List.unmodifiable(items), _clock());
    _items += items.length;
    while (_entries.length > maxEntries || _items > maxItems) {
      final oldest = _entries.keys.first;
      _items -= _entries.remove(oldest)!.items.length;
    }
  }

  void clear() {
    _entries.clear();
    _items = 0;
  }
}

final class _CachedListing {
  const _CachedListing(this.items, this.storedAt);

  final List<WebDavItem> items;
  final DateTime storedAt;
}
