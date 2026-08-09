import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Appearance category's DPAD wiring is POSITIONAL: `_paneKey` moves focus
/// by node index ± 1, so the numbering IS the on-screen order. Splitting the
/// category into four `SettingsSection`s made that easy to get wrong — a group
/// boundary is exactly where someone renumbers by hand and skips or repeats a
/// value, and the symptom is a row the remote silently steps over.
///
/// A source-level test because the failure is structural, not visual: the
/// widget renders fine either way.
void main() {
  late String appearance;

  setUpAll(() {
    final src = File('lib/screens/settings/settings_tv_layout.dart')
        .readAsStringSync();
    final start = src.indexOf('case 3: // Appearance');
    final end = src.indexOf('case 4: // Playback', start);
    expect(start, isNonNegative, reason: 'Appearance case not found');
    appearance = src.substring(start, end);
  });

  test('pane focus indices are contiguous from zero across every group', () {
    final indices = RegExp(r'_paneNodes\[(\d+)\]')
        .allMatches(appearance)
        .map((m) => int.parse(m.group(1)!))
        .toList();

    expect(indices, isNotEmpty);
    expect(
      indices,
      List<int>.generate(indices.length, (i) => i),
      reason: 'a gap skips a row on the way down; a repeat means two widgets '
          'share one FocusNode and one becomes unreachable',
    );
  });

  test('the node pool covers the category', () {
    final src = File('lib/screens/settings/settings_tv_layout.dart')
        .readAsStringSync();
    final pool = int.parse(
      RegExp(r'_kMaxCategoryRows = (\d+)').firstMatch(src)!.group(1)!,
    );
    final highest = RegExp(r'_paneNodes\[(\d+)\]')
        .allMatches(appearance)
        .map((m) => int.parse(m.group(1)!))
        .reduce((a, b) => a > b ? a : b);
    expect(
      highest,
      lessThan(pool),
      reason: 'a row past the pool throws on build',
    );
  });

  test('every group carries a header and an explanation', () {
    // The whole point of the reorganisation: four kinds of decision that used
    // to interleave now say which kind they are.
    for (final title in ['Presets', 'Theme', 'Screen layouts', 'Display']) {
      expect(appearance, contains("title: '$title'"), reason: title);
    }
    expect(
      RegExp(r'blurb:').allMatches(appearance).length,
      4,
      reason: 'a header without a blurb is the ambiguity we just removed',
    );
  });
}
