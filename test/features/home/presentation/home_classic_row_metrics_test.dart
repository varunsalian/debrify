import 'dart:math';
import 'package:debrify/features/home/presentation/home_classic_row_metrics.dart';
import 'package:debrify/widgets/home/row_tag_pill.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'poster metrics retain phone breakpoint and TV floor/ceiling budgets',
    (tester) async {
      for (final scenario in [
        (size: const Size(899, 600), tv: false, search: false, expected: 118.0),
        (size: const Size(900, 600), tv: false, search: false, expected: 162.0),
        (size: const Size(1920, 400), tv: true, search: false, expected: 92.0),
        (size: const Size(1920, 720), tv: true, search: false, expected: 122.4),
        (
          size: const Size(1920, 1080),
          tv: true,
          search: false,
          expected: 140.0,
        ),
        (size: const Size(1920, 400), tv: true, search: true, expected: 120.0),
        (size: const Size(1920, 720), tv: true, search: true, expected: 162.0),
        (size: const Size(1920, 1080), tv: true, search: true, expected: 180.0),
      ]) {
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: scenario.size),
            child: Builder(
              builder: (context) {
                expect(
                  homeRailPosterWidth(
                    context,
                    isTelevision: scenario.tv,
                    searchResults: scenario.search,
                  ),
                  closeTo(scenario.expected, .00001),
                );
                return const SizedBox();
              },
            ),
          ),
        );
      }
    },
  );

  test(
    'orientation and hero sizing preserve one-row clearance and compact Search',
    () {
      expect(
        homeClassicCardSize(posterWidth: 120, landscape: false),
        const Size(120, 180),
      );
      expect(
        homeClassicCardSize(posterWidth: 120, landscape: true),
        const Size(192, 108),
      );
      expect(homeTitleCardAspect(landscape: false), 2 / 3);
      expect(homeTitleCardAspect(landscape: true), 16 / 9);
      expect(
        homeClassicHeroBudget(
          boardHeight: 540,
          cardHeight: 180,
          isTelevision: true,
          searchResults: false,
        ),
        278,
      );
      expect(
        homeClassicHeroBudget(
          boardHeight: 540,
          cardHeight: 180,
          isTelevision: false,
          searchResults: false,
        ),
        270,
      );
      expect(
        homeClassicHeroBudget(
          boardHeight: 100,
          cardHeight: 180,
          isTelevision: true,
          searchResults: false,
        ),
        150,
      );
      expect(
        homeClassicHeroBudget(
          boardHeight: 2000,
          cardHeight: 180,
          isTelevision: true,
          searchResults: false,
        ),
        440,
      );
      expect(
        homeClassicHeroBudget(
          boardHeight: 2000,
          cardHeight: 180,
          isTelevision: true,
          searchResults: true,
        ),
        150,
      );
    },
  );

  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'anchor measurement matches rendered title/tag at $direction scale $scale',
        (tester) async {
          var hideTags = false;
          var cardHeight = 180.0;
          double? extent;
          final reads = <String>[];
          const titleStyle = TextStyle(
            fontSize: 8,
            height: 1,
            fontWeight: FontWeight.w600,
          );
          Widget page() => MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Directionality(
              textDirection: direction,
              child: DefaultTextStyle(
                style: const TextStyle(fontSize: 10, height: 1),
                child: Builder(
                  builder: (context) {
                    extent = measureHomeClassicRowExtent(
                      context,
                      hideHeader: false,
                      hideSourceTags: hideTags,
                      titleStyle: () {
                        reads.add('style');
                        return titleStyle;
                      },
                      cardHeight: () {
                        reads.add('height');
                        return cardHeight;
                      },
                    );
                    return Column(
                      children: [
                        const Text(
                          'Ag',
                          key: ValueKey('title'),
                          style: titleStyle,
                        ),
                        Text(
                          'Ag',
                          key: const ValueKey('tag'),
                          style: RowTagPill.textStyle(9.5),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pumpWidget(page());
          final titleHeight = tester
              .getSize(find.byKey(const ValueKey('title')))
              .height;
          final tagHeight =
              tester.getSize(find.byKey(const ValueKey('tag'))).height +
              9.5 * .56 +
              2;
          expect(tagHeight, greaterThan(titleHeight));
          expect(extent, 14 + max(titleHeight, tagHeight) + 10 + 180 + 14);
          expect(reads, ['style', 'height']);
          reads.clear();
          hideTags = true;
          cardHeight = 220;
          await tester.pumpWidget(page());
          expect(extent, 14 + titleHeight + 10 + 220 + 14);
          expect(reads, ['style', 'height']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'hidden collection header avoids font and inherited text lookups entirely',
    (tester) async {
      var heightReads = 0;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            expect(
              measureHomeClassicRowExtent(
                context,
                hideHeader: true,
                hideSourceTags: false,
                titleStyle: () =>
                    throw StateError('Hidden header requested a font'),
                cardHeight: () {
                  heightReads++;
                  return 180;
                },
              ),
              202,
            );
            return const SizedBox();
          },
        ),
      );
      expect(heightReads, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
