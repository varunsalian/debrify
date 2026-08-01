import 'package:debrify/widgets/see_all/see_all_filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The bar collapses its chips into a "Filters" button on a narrow non-TV
/// canvas — except when it is quiet, where the line is already the compact
/// form. Discover and the See-All screens depend on the collapse; the IPTV
/// two-pane guide column depends on the exception, because its pane sits under
/// the threshold even when the window is wide.
void main() {
  Widget host({
    required bool quiet,
    required double width,
    bool isTelevision = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: SeeAllFilterBar(
              isTelevision: isTelevision,
              quiet: quiet,
              buildChips: () => const [Text('chip-source'), Text('chip-genre')],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a narrow non-TV bar collapses into the Filters button', (
    tester,
  ) async {
    await tester.pumpWidget(host(quiet: false, width: 400));

    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('chip-source'), findsNothing);
    expect(find.text('chip-genre'), findsNothing);
  });

  testWidgets('a wide non-TV bar shows its chips inline', (tester) async {
    await tester.pumpWidget(host(quiet: false, width: 900));

    expect(find.text('Filters'), findsNothing);
    expect(find.text('chip-source'), findsOneWidget);
  });

  testWidgets('a quiet bar stays inline however narrow the pane', (
    tester,
  ) async {
    await tester.pumpWidget(host(quiet: true, width: 400));

    expect(find.text('Filters'), findsNothing);
    expect(find.text('chip-source'), findsOneWidget);
    expect(find.text('chip-genre'), findsOneWidget);
  });

  testWidgets('a quiet bar separates its segments with dots', (tester) async {
    await tester.pumpWidget(host(quiet: true, width: 400));

    // Two chips, so exactly one separator between them.
    final separators = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(SeeAllFilterBar),
        matching: find.byType(Container),
      ),
    );
    expect(
      separators.where((c) {
        final decoration = c.decoration;
        return decoration is BoxDecoration &&
            decoration.shape == BoxShape.circle;
      }).length,
      1,
    );
  });

  testWidgets('a quiet bar never collapses on TV either', (tester) async {
    await tester.pumpWidget(host(quiet: true, width: 400, isTelevision: true));

    expect(find.text('Filters'), findsNothing);
    expect(find.text('chip-source'), findsOneWidget);
  });
}
