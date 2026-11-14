import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/widgets/detail/showcase_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/detail_showcase_fixture.dart';

/// Reported on Discord: on a TV, a long trivia or goof card ended in "…" and
/// could not be opened, so the rest of it was unreadable.
void main() {
  final long = List.filled(60, 'Gagné blocks Turbo on the straight.').join(' ');
  final entries = [DidYouKnowEntry(kind: 'Goof', text: long)];

  Finder reader() => find.byType(Dialog);

  testWidgets('OK opens the full text, arrows scroll it, OK closes it and '
      'focus returns to the card', (t) async {
    await showcaseCase(t, (f) async {
      final node = f.node('dyk');
      await t.pumpWidget(
        f.host(
          ShowcaseDidYouKnow(
            entries: entries,
            total: 1,
            countLine: null,
            nodes: [node],
          ),
        ),
      );
      await showcasePump(t);
      node.requestFocus();
      await showcasePump(t);

      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(reader(), findsOneWidget);
      expect(
        find.descendant(of: reader(), matching: find.text(long)),
        findsOneWidget,
      );

      double offset() => t
          .state<ScrollableState>(
            find.descendant(of: reader(), matching: find.byType(Scrollable)),
          )
          .position
          .pixels;
      expect(offset(), 0);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(offset(), greaterThan(0));

      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(reader(), findsNothing);
      expect(node.hasFocus, isTrue);
    }, television: true);
  });

  testWidgets('a click opens the reader too', (t) async {
    await showcaseCase(t, (f) async {
      await t.pumpWidget(
        f.host(
          ShowcaseDidYouKnow(
            entries: entries,
            total: 1,
            countLine: null,
            nodes: [f.node('dyk')],
          ),
        ),
      );
      await showcasePump(t);
      await t.tap(find.text('GOOF'));
      await t.pumpAndSettle();
      expect(reader(), findsOneWidget);
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(reader(), findsNothing);
    });
  });
}
