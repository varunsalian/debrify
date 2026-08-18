/// URI-safe helpers for Stremio's path-based protocol.
///
/// Configured addon URLs may carry authentication in their query string.
/// Resource paths must be changed without appending text after that query.
Uri normalizeStremioManifestUri(String raw) {
  var uri = Uri.parse(raw.trim());
  if (uri.scheme.toLowerCase() == 'stremio') {
    uri = uri.replace(scheme: 'https');
  }
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (segments.isEmpty || segments.last != 'manifest.json') {
    segments.add('manifest.json');
  }
  return uri.replace(pathSegments: segments);
}

/// Derives the addon root while preserving query authentication and fragments.
Uri stremioBaseUriFromManifest(String manifestUrl) {
  final uri = normalizeStremioManifestUri(manifestUrl);
  final segments = uri.pathSegments.toList();
  if (segments.isNotEmpty && segments.last == 'manifest.json') {
    segments.removeLast();
  }
  return uri.replace(pathSegments: segments);
}

/// Appends already URI-encoded Stremio path segments before query/fragment.
///
/// Callers historically encode dynamic IDs before constructing the endpoint,
/// so resource segments are retained byte-for-byte. Existing base segments are
/// canonicalized once, preventing query corruption and percent double-encoding.
Uri buildStremioResourceUri(
  String baseUrl,
  Iterable<String> encodedResourceSegments,
) {
  final base = Uri.parse(baseUrl.trim());
  final encodedSegments = <String>[
    for (final part in base.pathSegments.where((part) => part.isNotEmpty))
      Uri.encodeComponent(part),
    ...encodedResourceSegments,
  ];
  if (!base.hasScheme || !base.hasAuthority) {
    throw FormatException('Stremio addon URL must be absolute', baseUrl);
  }
  final origin = '${base.scheme}://${base.authority}';
  final query = base.hasQuery ? '?${base.query}' : '';
  final fragment = base.hasFragment ? '#${base.fragment}' : '';
  return Uri.parse('$origin/${encodedSegments.join('/')}$query$fragment');
}
