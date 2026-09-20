import 'package:debrify/utils/iptv_title.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recall-oriented alternatives keep provider variants and missing years',
    () {
      for (final name in [
        'PCOK - The Office (2005)',
        'IT - The Office (US) (2005) (US)',
        'ABCXYZ - The Office (2005)',
        'FR - The Office',
      ]) {
        expect(
          IptvTitle.matches(name, 'The Office', year: 2005),
          isTrue,
          reason: name,
        );
      }
      for (final name in [
        'TOP - 1917',
        'GR - 1917 (2019)',
        'IL - 1917 (2019)',
        'RO - 1917 (2019)',
        'KU-S - 1917 (2019)',
        'EN-TOP - 122. 1917 (2019)',
      ]) {
        expect(
          IptvTitle.matches(name, '1917', year: 2019),
          isTrue,
          reason: name,
        );
      }
      expect(
        IptvTitle.matches(
          'PCOK - The Office (2024) (AU)',
          'The Office',
          year: 2005,
        ),
        isFalse,
      );
      expect(
        IptvTitle.matches(
          'PCOK - The Office Movers (2024)',
          'The Office',
          year: 2024,
        ),
        isFalse,
      );
      expect(
        IptvTitle.matches('NL - Total Recall', 'Total Recall', year: 1990),
        isTrue,
      );
      expect(
        IptvTitle.matches('NL - Total Recall', 'Total Recall', year: 2012),
        isTrue,
      );
    },
  );
  for (final prefix in [
    'NF - ',
    'MRVL - ',
    '4K-MRVL - ',
    'EN - ',
    'ES - ',
    'FR - ',
    'IN - ',
    '[EN] ',
    '|DE| ',
    'EN│',
  ]) {
    test('matches provider prefix $prefix', () {
      expect(
        IptvTitle.matches(
          '${prefix}The Avengers (2012)',
          'The Avengers',
          year: 2012,
        ),
        isTrue,
      );
      expect(
        IptvTitle.matches(
          '${prefix}The Avengers (1998)',
          'The Avengers',
          year: 2012,
        ),
        isFalse,
      );
    });
  }
  test('retains identity words and numeric titles', () {
    for (final title in [
      '1917',
      '2012',
      '2001: A Space Odyssey',
      'Blade Runner 2049',
      'It: Chapter Two',
      'DUNE - Part Two',
      'ALIEN - Covenant',
      'Amélie',
      '天空之城',
    ]) {
      expect(
        IptvTitle.matches('$title (2019)', title, year: 2019),
        isTrue,
        reason: title,
      );
    }
    expect(
      IptvTitle.matches('Blade Runner 2049', 'Blade Runner', year: 1982),
      isFalse,
    );
    expect(
      IptvTitle.matches('DUNE - Part Two (2024)', 'Dune', year: 2024),
      isFalse,
    );
    expect(IptvTitle.matches('AKA - 2023', 'AKA', year: 2023), isTrue);
    expect(IptvTitle.matches('IT - 65 (2023)', '65', year: 2023), isTrue);
    expect(
      IptvTitle.matches('EN - The Avengers 1080p', 'The Avengers', year: 2012),
      isTrue,
    );
    expect(
      IptvTitle.matches(
        'EN - The Avengers (2012) 4K',
        'The Avengers',
        year: 2012,
      ),
      isTrue,
    );
    expect(
      IptvTitle.matches(
        'The Avengers: Age of Ultron',
        'The Avengers',
        year: 2012,
      ),
      isFalse,
    );
  });
}
