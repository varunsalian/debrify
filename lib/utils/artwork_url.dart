/// Returns MetaHub's high-resolution equivalent of an artwork URL.
///
/// MetaHub catalog payloads intentionally use `medium` images for shelves,
/// where a smaller transfer and decode are the right trade-off. A full-screen
/// hero is the exception: it is enlarged to the display and needs the larger
/// source. URLs from every other provider are returned unchanged.
String? highQualityArtworkUrl(String? url) {
  if (url == null || url.isEmpty) return url;

  final uri = Uri.tryParse(url);
  if (uri?.host.toLowerCase() != 'images.metahub.space') return url;

  return url
      .replaceFirst('/poster/medium/', '/poster/large/')
      .replaceFirst('/background/medium/', '/background/large/');
}
