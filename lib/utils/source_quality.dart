/// Resolution encoded in a source/release name.
enum SourceQuality { ultraHd, fullHd, hd, sd }

/// Detects the displayed resolution of a source name.
///
/// Explicit pixel resolutions are authoritative. Loose marketing/source
/// tokens such as `4K` and `UHD` are only fallbacks, and must be standalone
/// tokens so release groups such as `DS4K` and `RM4k` are not misclassified.
SourceQuality? sourceQualityForName(String name) {
  if (name.isEmpty) return null;

  bool has(String pattern) => RegExp(
    r'(?:^|[^A-Za-z0-9])(?:' + pattern + r')(?=$|[^A-Za-z0-9])',
    caseSensitive: false,
  ).hasMatch(name);

  if (has(r'2160p')) return SourceQuality.ultraHd;
  if (has(r'1080p|1080i')) return SourceQuality.fullHd;
  if (has(r'720p|720i')) return SourceQuality.hd;
  if (has(r'480p|576p|360p')) return SourceQuality.sd;

  if (has(r'FHD|Full[ .-]?HD')) return SourceQuality.fullHd;
  if (has(r'4K|UHD')) return SourceQuality.ultraHd;
  return null;
}

String? sourceQualityBadgeForName(String name) =>
    switch (sourceQualityForName(name)) {
      SourceQuality.ultraHd => '4K',
      SourceQuality.fullHd => '1080p',
      SourceQuality.hd => '720p',
      SourceQuality.sd => '480p',
      null => null,
    };
