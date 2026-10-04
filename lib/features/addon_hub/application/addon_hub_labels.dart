String addonHubCapitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Map a manifest's `resources` to user-facing capability labels, in importance
/// order. The `bool` is "highlight" — Streams is what Debrify is built around,
/// so it's the accented chip. Unknown/irrelevant resources are dropped.
List<(String, bool)> addonHubCapabilities(List<String> resources) {
  const order = <String, (String, bool)>{
    'stream': ('Streams', true),
    'catalog': ('Catalog', false),
    'meta': ('Metadata', false),
    'subtitles': ('Subtitles', false),
    'addon_catalog': ('Addon list', false),
  };
  final out = <(String, bool)>[];
  for (final entry in order.entries) {
    if (resources.contains(entry.key)) out.add(entry.value);
  }
  return out;
}
