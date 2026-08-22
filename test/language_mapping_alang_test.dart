import 'package:debrify/screens/video_player/utils/language_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alang lists the canonical code first, then tag-shaped variants', () {
    final alang = LanguageMapper.alangForCode('en').split(',');
    expect(alang.first, 'en');
    expect(alang, contains('eng'));
    expect(alang, contains('en-us'));
    // Display names never appear in container metadata.
    expect(alang, isNot(contains('english')));
  });

  test('alang resolves variant input to its canonical language', () {
    expect(LanguageMapper.alangForCode('eng').split(',').first, 'en');
    expect(LanguageMapper.alangForCode('spa').split(',').first, 'es');
  });

  test('alang passes unknown codes through and empties stay empty', () {
    expect(LanguageMapper.alangForCode('xx'), 'xx');
    expect(LanguageMapper.alangForCode(''), '');
    expect(LanguageMapper.alangForCode('  '), '');
  });

  test('audio rows label auto as Automatic and number real tracks past it', () {
    final rows = LanguageMapper.audioTrackOptions<(String, String)>(
      [
        (id: 'auto', language: null, title: null),
        (id: '1', language: null, title: null),
        (id: '2', language: 'eng', title: null),
      ],
      (id, label) => (id, label),
    );
    expect(rows, [
      ('auto', 'Automatic'),
      ('1', 'Track 1'), // not "Track 2": the pseudo-entry doesn't count
      ('2', 'English'),
    ]);
  });
}
