import 'package:debrify/features/search/presentation/search_header.dart';
import 'package:debrify/ui/core/shell_nav_clearance.dart';
import 'package:debrify/widgets/browse/browse_search_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _fieldKey = ValueKey('field');

Widget _page(Widget child, {ShellNavClearance Function(Widget)? wrap}) {
  final page = Align(alignment: Alignment.topLeft, child: child);
  return MaterialApp(home: Scaffold(body: wrap == null ? page : wrap(page)));
}

ShellNavClearance _capsule(Widget child) =>
    ShellNavClearance(leading: 76, below: 66, child: child);

void main() {
  group('extra padding', () {
    late BuildContext captured;
    Widget probe() => Builder(
      builder: (context) {
        captured = context;
        return const SizedBox();
      },
    );

    testWidgets('is zero without a capsule', (tester) async {
      await tester.pumpWidget(probe());
      expect(ShellNavClearance.extraLeading(captured, 20), 0);
      expect(ShellNavClearance.extraBelow(captured, 24), 0);
    });

    testWidgets('tops a row up to the capsule edge, never below zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        ShellNavClearance(leading: 76, below: 66, child: probe()),
      );
      expect(ShellNavClearance.extraLeading(captured, 20), 56);
      expect(ShellNavClearance.extraLeading(captured, 100), 0);
      expect(ShellNavClearance.extraBelow(captured, 24), 42);
      expect(ShellNavClearance.extraBelow(captured, 80), 0);
    });
  });

  group('browse search header (IPTV, YouTube)', () {
    Widget header() => SizedBox(
      width: 600,
      child: BrowseSearchHeader(
        key: _fieldKey,
        controller: TextEditingController(),
        focusNode: FocusNode(),
        hintText: 'Search YouTube...',
        onClear: () {},
      ),
    );

    double fieldLeft(WidgetTester tester) => tester
        .getTopLeft(
          find.descendant(
            of: find.byKey(_fieldKey),
            matching: find.byType(TextField),
          ),
        )
        .dx;

    testWidgets('keeps its shipped inset without a capsule', (tester) async {
      await tester.pumpWidget(_page(header()));
      expect(fieldLeft(tester), 20);
    });

    testWidgets('starts past the capsule when one floats over it', (
      tester,
    ) async {
      await tester.pumpWidget(_page(header(), wrap: _capsule));
      expect(fieldLeft(tester), 76);
    });
  });

  group('narrow search header', () {
    Widget header() => SizedBox(
      width: 500,
      child: SearchHeader(
        tv: false,
        dedicatedSearch: true,
        narrow: true,
        compactModeMenu: false,
        field: const SizedBox(key: _fieldKey, height: 44),
        toggle: const SizedBox(height: 40),
      ),
    );

    testWidgets('keeps its shipped inset without a capsule', (tester) async {
      await tester.pumpWidget(_page(header()));
      expect(tester.getTopLeft(find.byKey(_fieldKey)).dx, 16);
    });

    testWidgets('starts past the capsule when one floats over it', (
      tester,
    ) async {
      await tester.pumpWidget(_page(header(), wrap: _capsule));
      expect(tester.getTopLeft(find.byKey(_fieldKey)).dx, 76);
    });
  });
}
