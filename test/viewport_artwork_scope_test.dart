import 'package:debrify/widgets/viewport_artwork_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

Widget probe(String id, {FocusNode? focus}) => Builder(
  builder: (context) => Focus(
    focusNode: focus,
    child: SizedBox(
      height: 100,
      child: Text('$id:${ViewportArtworkScope.enabledOf(context)}'),
    ),
  ),
);

void main() {
  testWidgets('outside the scope artwork is unchanged', (tester) async {
    await tester.pumpWidget(MaterialApp(home: probe('plain')));
    expect(find.text('plain:true'), findsOneWidget);
  });

  testWidgets('mounts focus targets but only admits nearby artwork', (
    tester,
  ) async {
    final scroll = ScrollController();
    final focus = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: ListView(
              controller: scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
              children: [
                ViewportArtworkScope(child: probe('near')),
                const SizedBox(height: 800),
                ViewportArtworkScope(child: probe('far', focus: focus)),
                const SizedBox(height: 500),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('near:true'), findsOneWidget);
    expect(find.text('far:false', skipOffstage: false), findsOneWidget);
    expect(focus.context, isNotNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    scroll.jumpTo(800);
    await tester.pumpAndSettle();
    expect(find.text('far:true', skipOffstage: false), findsOneWidget);
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('far:true', skipOffstage: false), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('admits bands moved into view by late layout changes', (
    tester,
  ) async {
    final gap = ValueNotifier<double>(800);
    addTearDown(gap.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: ValueListenableBuilder<double>(
              valueListenable: gap,
              builder: (_, height, _) => ListView(
                scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
                children: [
                  SizedBox(height: height),
                  ViewportArtworkScope(child: probe('moving')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('moving:false', skipOffstage: false), findsOneWidget);
    gap.value = 50;
    await tester.pumpAndSettle();
    expect(find.text('moving:true'), findsOneWidget);
  });

  testWidgets('covered routes do not begin optional artwork until returning', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: SizedBox(
            height: 200,
            child: ListView(
              controller: scroll,
              scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
              children: [
                const SizedBox(height: 800),
                ViewportArtworkScope(child: probe('covered')),
                const SizedBox(height: 500),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('other')),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(750);
    await tester.pumpAndSettle();
    expect(find.text('covered:false', skipOffstage: false), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('covered:true'), findsOneWidget);
  });
}
