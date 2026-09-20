// Adapted from IPTVnator's title-normalization.util.ts:
// https://github.com/4gray/iptvnator/blob/master/libs/shared/interfaces/src/lib/title-normalization.util.ts
// MIT License
// Copyright (c) 2019-2026 4gray
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

/// Local, dependency-free provider-title parsing; does not fetch metadata.
/// Adapted subset of IPTVnator: separator-aware prefixes and exact/base keys.
/// Unlike upstream, preserve bracketed title words and require exact movie years.
class IptvTitle {
  const IptvTitle({required this.exact, required this.base, this.year});

  final String exact;
  final String base;
  final int? year;

  static const _pipes = r'[|¦│┃❘∣⏐⎪︱︳丨｜]';
  static const _quality = {
    '4k',
    'uhd',
    'fhd',
    'hd',
    'sd',
    'hdr',
    'hevc',
    'h264',
    'h265',
    'x264',
    'x265',
    '480p',
    '720p',
    '1080p',
    '2160p',
    'multi',
    'multisub',
    'vostfr',
    'vf',
    'dubbed',
  };
  static const _knownPrefixes = {
    'EN',
    'ENG',
    'ES',
    'FR',
    'DE',
    'IT',
    'IN',
    'AR',
    'PT',
    'RU',
    'TR',
    'NL',
    'PL',
    'NF',
    'MRVL',
    'AMZ',
    'OSN',
    'SUB',
    'SUBS',
    'TOP',
    'GR',
    'IL',
    'RO',
    'KU',
    'PCOK',
    'MAX',
  };
  // Keep regex fragments raw to make escaping auditable.
  // ignore: prefer_interpolation_to_compose_strings
  static final _prefix = RegExp(
    // ignore: prefer_interpolation_to_compose_strings
    r'^(?:([A-Z0-9+]{2,5}(?:-[A-Z0-9+]{2,6}){1,2}|[A-Z]{2,3}|MRVL)\s*-\s+'
            r'|([A-Z0-9+]{2,5})\s*' +
        _pipes +
        r'\s*|([A-Z]{2,3})\s*:\s*)',
  );
  static final _wrapped = RegExp(
    r'^(?:\[([A-Z0-9+]{2,5})\]|' +
        _pipes +
        r'([A-Z0-9+]{2,5})' +
        _pipes +
        r')\s*',
  );
  static final _year = RegExp(r'(?:\s+|^)((?:19|20)\d{2})$');
  static final _regionSuffix = RegExp(
    r'\s*[\[(](?:US|UK|GB|CA|AU|FR|DE|ES|IT|IN|JP|KR|TR|BR|MX|RU|CN)[\])]',
  );
  // Only a fallback interpretation. Unlike destructive normalization this can
  // accept unfamiliar provider tags without changing the canonical title.
  static final _providerVariant = RegExp(
    r'^([A-Z0-9+]{2,6}(?:-[A-Z0-9+]{1,6}){0,3})\s*[-:|]\s+',
  );

  /// Comparison folding preserves non-Latin letters and numeric title words.
  static String comparisonKey(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();

  static String _rest(String value) => comparisonKey(
    value,
  ).split(' ').where((word) => !_quality.contains(word)).join(' ').trim();

  static IptvTitle parse(String raw) {
    var value = raw.trim();
    // Bounded repeat supports stacked provider tags without stripping title words.
    for (var i = 0; i < 4; i++) {
      final match = _wrapped.firstMatch(value) ?? _prefix.firstMatch(value);
      if (match == null) break;
      final token = List.generate(
        match.groupCount,
        (i) => match.group(i + 1),
      ).whereType<String>().first;
      if (!RegExp('[A-Z]').hasMatch(token)) break;
      final remainder = value.substring(match.end).trim();
      final folded = _rest(remainder);
      final head = token.split('-').first;
      final known =
          _knownPrefixes.contains(head) ||
          _quality.contains(head.toLowerCase());
      if (folded.isEmpty ||
          (!known && !RegExp(r'\p{L}', unicode: true).hasMatch(folded))) {
        break;
      }
      value = remainder;
    }
    final exact = _rest(value);
    final suffix = _year.firstMatch(exact);
    final base = suffix == null
        ? exact
        : exact.substring(0, suffix.start).trim();
    // "1917" is a title, not an empty title plus a year.
    return IptvTitle(
      exact: exact,
      base: base.isEmpty ? exact : base,
      year: suffix == null || base.isEmpty ? null : int.parse(suffix.group(1)!),
    );
  }

  /// Compare provider spelling against a canonical metadata title.
  /// Exact keys first keep "Blade Runner 2049" distinct from "Blade Runner".
  static bool matches(String providerTitle, String title, {int? year}) {
    final expected = comparisonKey(title);
    if (expected.isEmpty) return false;
    bool accepts(String value) {
      final candidate = parse(value);
      if (candidate.exact == expected) return true;
      return candidate.base == expected &&
          (year == null || candidate.year == null || candidate.year == year);
    }

    // Preserve the original interpretation before trying known region metadata.
    // Never strip arbitrary parenthetical words (specials, subtitles, remakes).
    if (accepts(providerTitle)) return true;
    final withoutRegion = providerTitle.replaceAll(_regionSuffix, ' ').trim();
    if (withoutRegion != providerTitle && accepts(withoutRegion)) return true;
    final prefix = _providerVariant.firstMatch(withoutRegion);
    if (prefix == null || !RegExp('[A-Z]').hasMatch(prefix.group(1)!)) {
      return false;
    }
    final remainder = withoutRegion.substring(prefix.end).trim();
    if (accepts(remainder)) return true;
    // Ranked provider collections: "EN-TOP - 122. 1917 (2019)".
    // Do not strip numbers from ordinary titles such as "12. ...".
    if (prefix.group(1)!.split('-').contains('TOP')) {
      final unranked = remainder.replaceFirst(RegExp(r'^\d{1,4}\.\s+'), '');
      if (unranked != remainder && accepts(unranked)) return true;
    }
    return false;
  }
}
