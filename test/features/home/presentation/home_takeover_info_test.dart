import 'package:debrify/features/home/presentation/home_takeover_info.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../theme/golden_harness.dart';
import '../../discover/presentation/observed_value.dart';

void main() {
  setUp(disableRuntimeFonts);

  testWidgets(
    'empty hero subscribes only to item and releases nested signals when cleared',
    (tester) async {
      final h = _Overlay();
      addTearDown(h.dispose);
      await h.mount(tester);
      expect(h.item.isObserved, isTrue);
      expect(h.enriched.isObserved, isFalse);
      expect(h.takeover.isObserved, isFalse);
      h.item.value = const StremioMeta(id: 'a', type: 'movie', name: 'Title');
      await tester.pump();
      expect(find.text('TITLE'), findsOneWidget);
      expect(h.enriched.isObserved, isTrue);
      expect(h.takeover.isObserved, isTrue);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      h.item.value = null;
      await tester.pump();
      expect(find.text('TITLE'), findsNothing);
      expect(h.enriched.isObserved, isFalse);
      expect(h.takeover.isObserved, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(h.item.isObserved, isFalse);
      h.item.value = const StremioMeta(id: 'b', type: 'movie', name: 'Later');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'metadata fallback and primary precedence preserve title, year and first three genres',
    (tester) async {
      final h = _Overlay();
      addTearDown(h.dispose);
      h.item.value = const StremioMeta(id: 'a', type: 'movie', name: 'Catalog');
      h.enriched.value = const StremioMeta(
        id: 'a',
        type: 'movie',
        name: 'Enriched',
        year: '1984',
        runtime: '125',
        imdbRating: 7.86,
        genres: ['Drama', 'Mystery', 'Crime', 'Fourth'],
      );
      await h.mount(tester);
      expect(find.text('CATALOG'), findsOneWidget);
      expect(find.text('ENRICHED'), findsNothing);
      expect(find.text('1984'), findsNothing);
      expect(find.text('2h 5m'), findsOneWidget);
      expect(find.text('7.9'), findsOneWidget);
      expect(find.text('DRAMA   •   MYSTERY   •   CRIME'), findsOneWidget);
      h.item.value = const StremioMeta(
        id: 'a',
        type: 'movie',
        name: 'Current',
        year: '2020',
        runtime: '90',
        imdbRating: 6.2,
        genres: ['Comedy'],
      );
      await tester.pump();
      expect(find.text('CURRENT'), findsOneWidget);
      expect(find.text('2020'), findsOneWidget);
      expect(find.text('1h 30m'), findsOneWidget);
      expect(find.text('6.2'), findsOneWidget);
      expect(find.text('COMEDY'), findsOneWidget);
      expect(find.text('2h 5m'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'takeover threshold and title rise reuse the constructed text across frames',
    (tester) async {
      final h = _Overlay();
      addTearDown(h.dispose);
      h.item.value = const StremioMeta(id: 'a', type: 'movie', name: 'Title');
      h.takeover.value = .001;
      await h.mount(tester);
      expect(find.text('TITLE'), findsNothing);
      h.takeover.value = .5;
      await tester.pump();
      final text = tester.widget<Text>(find.text('TITLE'));
      double titleOpacity() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.text('TITLE'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      double titleRise() => tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.text('TITLE'),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .storage[13];
      expect(titleOpacity(), 0);
      expect(titleRise(), 14);
      h.takeover.value = .65;
      await tester.pump();
      expect(titleOpacity(), closeTo(.5, 1e-9));
      expect(titleRise(), closeTo(1.75, 1e-9));
      expect(tester.widget<Text>(find.text('TITLE')), same(text));
      h.takeover.value = .8;
      await tester.pump();
      expect(titleOpacity(), 1);
      expect(titleRise(), 0);
      expect(tester.widget<Text>(find.text('TITLE')), same(text));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settled overlay preserves lower-left placement and passes taps to the board',
    (tester) async {
      final h = _Overlay();
      addTearDown(h.dispose);
      h.item.value = const StremioMeta(id: 'a', type: 'movie', name: 'Title');
      var taps = 0;
      await h.mount(tester, onTap: () => taps++);
      final title = tester.getRect(find.text('TITLE'));
      expect(title.left, closeTo(77, .01));
      final column = find
          .ancestor(of: find.text('TITLE'), matching: find.byType(Column))
          .first;
      expect(tester.getRect(column).bottom, closeTo(666, .01));
      await tester.tapAt(title.center);
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      expect(h.item.isObserved, isFalse);
      expect(h.enriched.isObserved, isFalse);
      expect(h.takeover.isObserved, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Overlay {
  final item = ObservedValue<StremioMeta?>(null);
  final enriched = ObservedValue<StremioMeta?>(null);
  final takeover = ObservedValue(1.0);

  Future<void> mount(WidgetTester tester, {VoidCallback? onTap}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: const SizedBox.expand(),
                ),
                buildHomeTakeoverInfo(
                  context,
                  heroItem: item,
                  heroEnriched: enriched,
                  heroTakeover: takeover,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void dispose() {
    item.dispose();
    enriched.dispose();
    takeover.dispose();
  }
}
