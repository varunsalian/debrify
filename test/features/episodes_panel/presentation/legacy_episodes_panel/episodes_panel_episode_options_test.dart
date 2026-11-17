// Reported on Discord: an episode card cuts its description off and offers no
// way to read the rest. The options sheet (⋮, or a held OK on a remote) shows
// it in full.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/episodes_panel_fixture.dart';

void main() {
  testWidgets('the options sheet shows the whole episode description', (
    t,
  ) async {
    final overview = List.filled(
      8,
      'The Harrigans lock down the Cotswolds and roll back into London.',
    ).join(' ');
    await episodesPanelCase(t, 'options-overview', 88, (f) async {
      f.videosOverride = [
        {
          'id': '${f.id}:1:1',
          'season': 1,
          'episode': 1,
          'title': 'Ace of Spades',
          'overview': overview,
          'released': '2026-01-01T00:00:00Z',
          'imdbRating': 8.7,
        },
      ];
      f.progressLoader = () async => {};
      await f.mount(t);
      await f.sheet(t);
      final text = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(overview),
      );
      expect(text, findsOneWidget);
      expect(t.widget<Text>(text).maxLines, isNull);
    });
  });
}
