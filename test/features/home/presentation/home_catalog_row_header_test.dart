import 'package:debrify/features/home/presentation/home_catalog_row_header.dart';
import 'package:debrify/ui/core/see_all_link.dart';
import 'package:debrify/widgets/home/row_tag_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../theme/golden_harness.dart' show disableRuntimeFonts;

void main() {
  for (final scenario in [
    (width: 479.0, television: false),
    (width: 480.0, television: false),
    (width: 800.0, television: false),
    (width: 400.0, television: true),
  ]) {
    testWidgets(
      'catalog header preserves title/tag geometry and See-all dispatch at $scenario',
      (tester) async {
        disableRuntimeFonts();
        tester.view.physicalSize = Size(scenario.width, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const title = 'A very long catalog heading that must stay on one line';
        var showTag = true;
        var showAction = true;
        var taps = 0;
        Widget page() => MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: Builder(
                builder: (context) => KeyedSubtree(
                  key: const ValueKey('header'),
                  child: buildHomeCatalogRowHeader(
                    context,
                    isTelevision: scenario.television,
                    title: title,
                    tag: showTag ? 'Long configured source name' : null,
                    onSeeAll: showAction ? () => taps++ : null,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(page());
        final compact = !scenario.television && scenario.width < 480;
        final padding = tester.widget<Padding>(
          find
              .descendant(
                of: find.byKey(const ValueKey('header')),
                matching: find.byType(Padding),
              )
              .first,
        );
        expect(
          padding.padding,
          EdgeInsets.fromLTRB(
            compact ? 16 : 24,
            scenario.television ? 14 : 22,
            compact ? 16 : 24,
            scenario.television ? 10 : 12,
          ),
        );
        final heading = tester.widget<Text>(find.text(title));
        expect(heading.maxLines, 1);
        expect(heading.overflow, TextOverflow.ellipsis);
        expect(
          heading.style!.fontSize,
          compact || scenario.television ? 15 : 17,
        );
        expect(heading.style!.fontWeight, FontWeight.w600);
        expect(
          tester.getSize(find.byType(RowTagPill)).width,
          lessThanOrEqualTo(150),
        );
        expect(
          tester.getTopLeft(find.byType(RowTagPill)).dx,
          greaterThan(tester.getTopLeft(find.text(title)).dx),
        );
        State? actionState;
        if (scenario.television) {
          expect(find.byType(SeeAllLink), findsNothing);
        } else {
          final action = tester.widget<SeeAllLink>(find.byType(SeeAllLink));
          expect(action.compact, compact);
          actionState = tester.state(find.byType(SeeAllLink));
          await tester.tap(find.text(compact ? 'All' : 'See All'));
          expect(taps, 1);
        }
        showTag = false;
        await tester.pumpWidget(page());
        expect(find.byType(RowTagPill), findsNothing);
        if (!scenario.television) {
          expect(tester.state(find.byType(SeeAllLink)), same(actionState));
        }
        showAction = false;
        await tester.pumpWidget(page());
        expect(find.byType(SeeAllLink), findsNothing);
        expect(taps, scenario.television ? 0 : 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'shared title style matches the rendered TV line under text scaling and RTL',
    (tester) async {
      disableRuntimeFonts();
      double? measuredHeight;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 600),
                textScaler: TextScaler.linear(2),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Builder(
                  builder: (context) {
                    final style = homeCatalogRowTitleStyle(
                      context,
                      fontSize: 15,
                    );
                    final painter = TextPainter(
                      text: TextSpan(
                        text: 'Ag',
                        style: DefaultTextStyle.of(context).style.merge(style),
                      ),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                      maxLines: 1,
                    )..layout();
                    measuredHeight = painter.height;
                    painter.dispose();
                    return Align(
                      alignment: Alignment.topCenter,
                      child: buildHomeCatalogRowHeader(
                        context,
                        isTelevision: true,
                        title: 'Ag',
                        tag: 'Source',
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.text('Ag')).height, measuredHeight);
      expect(
        tester.getTopLeft(find.byType(RowTagPill)).dx,
        lessThan(tester.getTopLeft(find.text('Ag')).dx),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
