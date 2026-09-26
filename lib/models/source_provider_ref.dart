/// One row of the Quick Play "Addon Priority" list: a place results come
/// from — a torrent search engine or a Stremio addon. Users see one flat
/// list; the distinction only matters for key normalization.
class SourceProviderRef {
  final String key; // 'engine:<id>' or configuration-specific addon/IPTV key
  final String name; // display name
  final bool isEngine;
  final Set<String> legacyKeys;
  bool get isIptv => key.startsWith('iptv:');

  const SourceProviderRef({
    required this.key,
    required this.name,
    required this.isEngine,
    this.legacyKeys = const <String>{},
  });
}
