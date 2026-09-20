// Title-only examples from the user's local 8K Strong catalog (2026-09-20).
// No provider endpoints, account identifiers, credentials or stream URLs.
import 'package:debrify/utils/iptv_title.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all 19 GoT title variants, not podcasts or anniversary specials', () {
    const titles = [
      '4K-OSN+ - Game of Thrones (2011) (US)',
      'EN - Game of Thrones (2011) (US)',
      'EN - Game of Thrones (US)',
      '4K-FR - Game of Thrones (2011) (US)',
      'FR - Game of Thrones',
      'IN - Game of Thrones (2011) (US)',
      '4K-DE-DV - Game of Thrones (2011) (US)',
      'DE - Game of Thrones (2011) (US)',
      '4K-DE - Game of Thrones (2011) (US)',
      'NL - Game of Thrones (2011) (US)',
      'GR - Game of Thrones',
      'SC - Game of Thrones (2011) (US)',
      'BG - Game of Thrones (2011)',
      '4K-TR - Game of Thrones (2011) (US)',
      'TR - Game of Thrones (2011) (US)',
      'IR - Game of Thrones',
      '4K-AR - Game of Thrones (2011) (US)',
      'AR-SUBS - Game of Thrones (2011) (US)',
      'AR-DE - Game of Thrones (2011) (US)',
    ];
    for (final title in titles) {
      expect(
        IptvSourceSearch.matches(title, 'Game of Thrones', '2011-2019'),
        isTrue,
        reason: title,
      );
    }
    for (final title in [
      'MAX - The Official Game of Thrones Podcast: House of the Dragon (2022) (ES)',
      'MAX - The Official Game of Thrones Podcast: A Knight of the Seven Kingdoms (2026) (US)',
      'EN - Game of Thrones: The Iron Anniversary (US)',
      'EN - Game of Thrones (1998) (US)',
    ]) {
      expect(
        IptvSourceSearch.matches(title, 'Game of Thrones', '2011-2019'),
        isFalse,
        reason: title,
      );
    }
  });
  test('movie remakes and related titles remain distinct', () {
    for (final title in [
      'EN - Dune  (2021)',
      'QC - Dune (2021)',
      'IN-EN - Dune (2021)',
      '4K-FR - Dune  (2021)',
    ]) {
      expect(IptvTitle.matches(title, 'Dune', year: 2021), isTrue);
    }
    for (final title in [
      'ES - Dune (1984)',
      'EN - Planet Dune  (2021)',
      'EN - Dune World  (2021)',
      'EN - The Dunes  (2021)',
      'TOP - Dune: Part Two (2024)',
    ]) {
      expect(IptvTitle.matches(title, 'Dune', year: 2021), isFalse);
    }
    expect(
      IptvTitle.matches(
        'AMZ - Blade Runner 2049 (2017)',
        'Blade Runner 2049',
        year: 2017,
      ),
      isTrue,
    );
    expect(
      IptvTitle.matches('NF - Blade Runner 2049', 'Blade Runner', year: 1982),
      isFalse,
    );
    expect(
      IptvTitle.matches('EN - The Avengers (1998)', 'The Avengers', year: 2012),
      isFalse,
    );
  });
}
