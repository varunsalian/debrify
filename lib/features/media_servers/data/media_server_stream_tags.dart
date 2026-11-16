/// Source tags from a media server's video stream (moved from
/// `MediaServerService`). Pure functions over the normalised stream keys.
class MediaServerStreamTags {
  const MediaServerStreamTags._();

  // Map cropped originals onto the tiers understood by the shared filters.
  // Both dimensions matter: a 1920x800 movie is still a Full HD source.
  static String quality(Map video) {
    final width = (video['Width'] as num?)?.toInt() ?? 0;
    final height = (video['Height'] as num?)?.toInt() ?? 0;
    if (width <= 0 && height <= 0) return 'Original';
    if (width > 2560 || height > 1440) return '2160p';
    if (width > 1280 || height > 962) return '1080p';
    if (width > 1024 || height > 576) return '720p';
    return height > 480 ? '576p' : '480p';
  }

  static List<String> dynamicRange(Map video) {
    final range = [
      video['VideoRangeType'],
      video['VideoRange'],
      video['ExtendedVideoType'],
    ].whereType<String>().join(' ').toUpperCase();
    final transfer = (video['ColorTransfer'] as String? ?? '').toLowerCase();
    final tags = <String>[];
    if (range.contains('DOVI') ||
        range.contains('DOLBY') ||
        RegExp(r'\bDV\b').hasMatch(range) ||
        ((video['DvProfile'] as num?) ?? 0) > 0) {
      tags.add('DV');
    }
    if (range.contains('HDR10PLUS') ||
        range.contains('HDR10+') ||
        video['Hdr10PlusPresentFlag'] == true) {
      tags.add('HDR10+');
    } else if (range.contains('HDR10') || transfer == 'smpte2084') {
      tags.add('HDR10');
    }
    if (range.contains('HLG') || transfer == 'arib-std-b67') tags.add('HLG');
    if (tags.isEmpty && range.contains('HDR')) tags.add('HDR');
    return tags;
  }
}
