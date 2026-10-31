// Telling apart the versions of one IPTV channel by name: providers list the
// same channel several times ("4K: ELEVEN SPORTS 1 ᵁᴴᴰ ³⁸⁴⁰ᴾ",
// "PL: ELEVEN SPORTS 1 ᴴᴰ", "Eleven Sports 1"), and a multi-view tile the box
// cannot decode can fall back to another one. Pure functions, no I/O.

/// Superscript and modifier letters providers decorate names with, folded to
/// plain ASCII so "ᴴᴰ" reads as "hd".
const _folded = {
  'ᴬ': 'a',
  'ᴮ': 'b',
  'ᴰ': 'd',
  'ᴱ': 'e',
  'ᴳ': 'g',
  'ᴴ': 'h',
  'ᴵ': 'i',
  'ᴶ': 'j',
  'ᴷ': 'k',
  'ᴸ': 'l',
  'ᴹ': 'm',
  'ᴺ': 'n',
  'ᴼ': 'o',
  'ᴾ': 'p',
  'ᴿ': 'r',
  'ᵀ': 't',
  'ᵁ': 'u',
  'ⱽ': 'v',
  'ᵂ': 'w',
  'ᵃ': 'a',
  'ᵇ': 'b',
  'ᶜ': 'c',
  'ᵈ': 'd',
  'ᵉ': 'e',
  'ᶠ': 'f',
  'ᵍ': 'g',
  'ʰ': 'h',
  'ⁱ': 'i',
  'ʲ': 'j',
  'ᵏ': 'k',
  'ˡ': 'l',
  'ᵐ': 'm',
  'ⁿ': 'n',
  'ᵒ': 'o',
  'ᵖ': 'p',
  'ʳ': 'r',
  'ˢ': 's',
  'ᵗ': 't',
  'ᵘ': 'u',
  'ᵛ': 'v',
  'ʷ': 'w',
  'ˣ': 'x',
  'ʸ': 'y',
  'ᶻ': 'z',
  '⁰': '0',
  '¹': '1',
  '²': '2',
  '³': '3',
  '⁴': '4',
  '⁵': '5',
  '⁶': '6',
  '⁷': '7',
  '⁸': '8',
  '⁹': '9',
  '⁺': '+',
};

/// Words that describe the stream, not the channel.
const _qualityWords = {
  '8k',
  '4k',
  'uhd',
  '2160p',
  '3840p',
  'fhd',
  '1080p',
  '1080i',
  '1080',
  'hd',
  '720p',
  'sd',
  '576p',
  '480p',
  'raw',
  'hevc',
  'h265',
  'h264',
  'vip',
  '50',
  '60',
  'fps',
  'hdr',
  'sdr',
  'dolby',
  'audio',
  'event',
  'backup',
};

String _fold(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    out.write(_folded[char] ?? char.toLowerCase());
  }
  return out.toString();
}

/// What a channel name says about its stream: 3 for 4K/UHD/8K, 2 for
/// FHD/1080 and RAW (an untouched broadcast feed), 1 for HD or no tag, 0 for
/// SD.
int channelQuality(String name) {
  final words = _fold(name).split(RegExp(r'[^a-z0-9+]+')).toSet();
  bool any(Set<String> tags) => words.any(tags.contains);
  if (any({'8k', '4k', '4k+', 'uhd', '2160p', '3840p'})) return 3;
  if (any({'fhd', '1080p', '1080i', '1080', 'raw'})) return 2;
  if (any({'sd', '576p', '480p'})) return 0;
  return 1;
}

/// A channel's identity across its versions: the region prefix (`pl` in
/// "PL: …", empty when none) and the name without quality words.
({String region, String base}) channelIdentity(String name) {
  var text = _fold(name).trim();
  var region = '';
  final prefix = RegExp(r'^([^:|]{1,12})[:|]\s*').firstMatch(text);
  if (prefix != null) {
    region = prefix.group(1)!.trim();
    text = text.substring(prefix.end);
  }
  final words = [
    for (final word in text.split(RegExp(r'[^a-z0-9]+')))
      if (word.isNotEmpty && !_qualityWords.contains(word)) word,
  ];
  // A "4K:" style prefix is a quality section, not a region.
  final regionIsQuality = _qualityWords.contains(
    region.replaceAll(RegExp(r'[^a-z0-9]'), ''),
  );
  return (region: regionIsQuality ? '' : region, base: words.join(' '));
}

/// The versions of [name] to try, best first, when the original cannot play.
/// A 4K original tries lower quality first (the device decodes HD where it
/// cannot take another 4K stream); anything else tries other copies at its
/// own quality first (its stream is the problem, not the decoder). Within
/// that, sharper first and the same region first. Never anything sharper
/// than the original, nor the original.
List<T> orderChannelVersions<T>({
  required String name,
  required String url,
  required List<T> candidates,
  required String Function(T) nameOf,
  required String Function(T) urlOf,
}) {
  final identity = channelIdentity(name);
  if (identity.base.isEmpty) return const [];
  final quality = channelQuality(name);
  final ranked = <(T, int)>[];
  for (final candidate in candidates) {
    if (urlOf(candidate) == url) continue;
    final other = channelIdentity(nameOf(candidate));
    if (other.base != identity.base) continue;
    final q = channelQuality(nameOf(candidate));
    if (q > quality) continue;
    final sameRegion =
        identity.region.isEmpty ||
        other.region.isEmpty ||
        other.region == identity.region;
    final preferred = quality == 3 ? q < quality : q == quality;
    final score = (preferred ? 0 : 1000) + (3 - q) * 10 + (sameRegion ? 0 : 1);
    ranked.add((candidate, score));
  }
  final seen = <String>{};
  return [
    for (final (candidate, _) in ranked..sort((a, b) => a.$2.compareTo(b.$2)))
      if (seen.add(urlOf(candidate))) candidate,
  ];
}
