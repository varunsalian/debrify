class ExtractedMedia {
  final String url;
  final String? audioUrl;
  final Map<String, String> headers;
  final List<dynamic>? sources;
  final String? provider;
  final List<Map<String, dynamic>>? externalSubtitles;

  ExtractedMedia({
    required this.url,
    this.audioUrl,
    required this.headers,
    this.sources,
    this.provider,
    this.externalSubtitles,
  });
}
