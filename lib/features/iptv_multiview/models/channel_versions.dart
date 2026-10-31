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
  'fps',
  'hdr',
  'sdr',
  'dolby',
  'audio',
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

/// Words in a name: letters of any script, digits and '+' (so "CANAL+" is
/// not "Canal", and "Футбол 1" keeps its first word).
final _word = RegExp(r'[\p{L}\p{N}+]+', unicode: true);

final _letter = RegExp(r'\p{L}', unicode: true);

List<String> _words(String text) => [
  for (final match in _word.allMatches(_fold(text))) match.group(0)!,
];

/// What a channel name says about its stream: 3 for 4K/UHD/8K, 2 for
/// FHD/1080 and RAW (an untouched broadcast feed), 1 for HD or no tag, 0 for
/// SD.
int channelQuality(String name) {
  final words = _words(name).toSet();
  bool any(Set<String> tags) => words.any(tags.contains);
  if (any({'8k', '4k', '4k+', 'uhd', '2160p', '3840p'})) return 3;
  if (any({'fhd', '1080p', '1080i', '1080', 'raw'})) return 2;
  if (any({'sd', '576p', '480p'})) return 0;
  return 1;
}

/// A channel's identity across its versions: its region (the first word of a
/// short "PL:" / "PL VIP:" style prefix; empty when there is none) and its
/// name without quality words. A long prefix ("Sky Sports: Main Event") is
/// part of the name, not a region.
({String region, String base}) channelIdentity(String name) {
  var text = _fold(name).trim();
  var region = '';
  final prefix = RegExp(r'^([^:|]{1,8})[:|]\s*').firstMatch(text);
  if (prefix != null) {
    final words = _words(prefix.group(1)!);
    if (words.isNotEmpty && words.length <= 2) {
      region = words.first;
      text = text.substring(prefix.end);
    }
  }
  // A "4K:" style prefix is a quality section, not a region.
  if (_qualityWords.contains(region) || region == '4k+') region = '';
  final base = [
    for (final word in _words(text))
      if (!_qualityWords.contains(word) && word != '4k+') word,
  ].join(' ');
  return (region: region, base: base);
}

/// The versions of [name] to try, best first, when the original cannot play.
/// Only the same channel counts: the same name without quality words, a
/// name with at least one letter, and never another region's feed (both
/// regions known and different). Same-region copies come first; then a 4K
/// original tries lower quality first (the device decodes HD where it cannot
/// take another 4K stream) and anything else tries copies at its own quality
/// first (its stream is the problem, not the decoder); sharper before
/// softer. Never anything sharper than the original, nor the original.
List<T> orderChannelVersions<T>({
  required String name,
  required String url,
  required List<T> candidates,
  required String Function(T) nameOf,
  required String Function(T) urlOf,
}) {
  final identity = channelIdentity(name);
  if (!_letter.hasMatch(identity.base)) return const [];
  final quality = channelQuality(name);
  final ranked = <(T, int)>[];
  for (final candidate in candidates) {
    if (urlOf(candidate) == url) continue;
    final other = channelIdentity(nameOf(candidate));
    if (other.base != identity.base) continue;
    final regionKnown = identity.region.isNotEmpty && other.region.isNotEmpty;
    if (regionKnown && other.region != identity.region) continue;
    final q = channelQuality(nameOf(candidate));
    if (q > quality) continue;
    final preferred = quality == 3 ? q < quality : q == quality;
    final score =
        (regionKnown ? 0 : 10000) + (preferred ? 0 : 1000) + (3 - q) * 10;
    ranked.add((candidate, score));
  }
  final seen = <String>{};
  return [
    for (final (candidate, _) in ranked..sort((a, b) => a.$2.compareTo(b.$2)))
      if (seen.add(urlOf(candidate))) candidate,
  ];
}
