import 'package:debrify/widgets/iptv/spotlight/keyboard_steady_layout_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reported on Discord: on a TV using the system keyboard, IPTV Spotlight's
/// search opened the keyboard for a moment and it closed again. Android
/// shrank the page above the keyboard, Spotlight fell back to the classic
/// layout, and the search field that held the keyboard went away.
class _Counted extends StatefulWidget {
  const _Counted();
  static int inits = 0;
  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    _Counted.inits++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late List<Size> seen;

  Future<void> pump(WidgetTester tester, double height, {bool on = true}) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 700,
              height: height,
              child: KeyboardSteadyLayoutBuilder(
                enabled: on,
                builder: (context, constraints) {
                  seen.add(constraints.biggest);
                  return const _Counted();
                },
              ),
            ),
          ),
        ),
      );

  void keyboard(WidgetTester tester, double bottom) =>
      tester.view.viewInsets = FakeViewPadding(bottom: bottom);

  setUp(() {
    seen = [];
    _Counted.inits = 0;
  });

  testWidgets('keeps the earlier size while the system keyboard is open', (
    tester,
  ) async {
    addTearDown(tester.view.resetViewInsets);
    await pump(tester, 540);
    keyboard(tester, 600);
    await pump(tester, 240);
    expect(seen.last, const Size(700, 540));
    expect(tester.takeException(), isNull);

    keyboard(tester, 0);
    await pump(tester, 540);
    expect(seen.last, const Size(700, 540));
    // The page under it was never rebuilt from scratch, so a focused search
    // field and its keyboard survive.
    expect(_Counted.inits, 1);
  });

  testWidgets('a shrink without the keyboard is a real resize', (tester) async {
    await pump(tester, 540);
    await pump(tester, 240);
    expect(seen.last, const Size(700, 240));
  });

  testWidgets('disabled, it is a plain LayoutBuilder', (tester) async {
    addTearDown(tester.view.resetViewInsets);
    await pump(tester, 540, on: false);
    keyboard(tester, 600);
    await pump(tester, 240, on: false);
    expect(seen.last, const Size(700, 240));
  });
}
