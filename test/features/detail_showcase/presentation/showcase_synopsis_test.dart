import 'package:debrify/features/detail_showcase/presentation/showcase_synopsis.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/detail_showcase_fixture.dart';

/// Reported on Discord: on a Mac and an Android tablet the series synopsis
/// stopped after three lines with no way to read the rest — and the text
/// itself was cut short by Cinemeta ("…when opposing forces col...").
void main() {
  final long = List.filled(
    12,
    'Two warring crime families clash in a battle for the city.',
  ).join(' ');

  Finder reader() => find.byType(Dialog);

  // The back button belongs to the screen's shell, not to the layout; mount a
  // stand-in so UP has somewhere real to land.
  Widget withBack(ShowcaseFixture f, Widget page) => Stack(
    fit: StackFit.expand,
    children: [
      Positioned(
        top: 0,
        left: 0,
        child: Focus(
          focusNode: f.back,
          child: const SizedBox.square(dimension: 1),
        ),
      ),
      page,
    ],
  );
  Finder more() => find.textContaining('MORE', findRichText: true);

  // MORE ends the THIRD line: not wrapped past it, where the clamp would clip
  // it away unseen, and not a line early with the band half empty.
  void expectMoreEndsTheThirdLine(WidgetTester t) {
    final paragraph = t.renderObject<RenderParagraph>(more());
    expect(paragraph.didExceedMaxLines, isFalse);
    final lines = TextPainter(
      text: paragraph.text,
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout(maxWidth: paragraph.size.width);
    expect(lines.computeLineMetrics(), hasLength(3));
    lines.dispose();
  }

  testWidgets('a cut synopsis offers MORE, which a click opens in full', (
    t,
  ) async {
    await showcaseCase(t, (f) async {
      await t.pumpWidget(
        f.host(f.page(value: f.model(description: long), dpad: false)),
      );
      await showcasePump(t);
      expect(more(), findsOneWidget);
      expectMoreEndsTheThirdLine(t);

      await t.tap(more());
      await t.pumpAndSettle();
      expect(reader(), findsOneWidget);
      expect(
        find.descendant(of: reader(), matching: find.text(long)),
        findsOneWidget,
      );
    });
  });

  testWidgets('MORE is placed in the style the text inherits', (t) async {
    // On a device the app theme supplies the font family; measured without
    // it, MORE landed a whole line early. Inherited spacing stands in for the
    // font here, since tests have only one.
    await showcaseCase(t, (f) async {
      await t.pumpWidget(
        f.host(
          DefaultTextStyle.merge(
            style: const TextStyle(letterSpacing: 3),
            child: f.page(value: f.model(description: long), dpad: false),
          ),
        ),
      );
      await showcasePump(t);
      expectMoreEndsTheThirdLine(t);
    });
  });

  testWidgets('a synopsis that fits has no MORE and UP still goes to Back', (
    t,
  ) async {
    await showcaseCase(t, (f) async {
      await t.pumpWidget(f.host(withBack(f, f.page(value: f.model()))));
      await showcasePump(t);
      expect(more(), findsNothing);

      f.primary.requestFocus();
      await showcasePump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await showcasePump(t);
      expect(f.back.hasFocus, isTrue);
    }, television: true);
  });

  testWidgets('on a remote MORE sits between the buttons and Back', (t) async {
    await showcaseCase(t, (f) async {
      await t.pumpWidget(
        f.host(withBack(f, f.page(value: f.model(description: long)))),
      );
      await showcasePump(t);
      f.primary.requestFocus();
      await showcasePump(t);

      FocusNode? focused() => FocusManager.instance.primaryFocus;

      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await showcasePump(t);
      expect(focused()?.debugLabel, 'showcase-synopsis');

      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(reader(), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.select);
      await t.pumpAndSettle();
      expect(reader(), findsNothing);
      expect(focused()?.debugLabel, 'showcase-synopsis');

      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await showcasePump(t);
      expect(f.primary.hasFocus, isTrue);

      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await showcasePump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await showcasePump(t);
      expect(f.back.hasFocus, isTrue);
    }, television: true);
  });

  testWidgets('once MORE is gone, UP from the buttons reaches Back again', (
    t,
  ) async {
    // MobLand's path: Cinemeta's long cut text shows MORE, then IMDb's plot
    // arrives and fits. A detached node keeps its stale context, so testing
    // `context != null` left UP aimed at a MORE that no longer exists.
    await showcaseCase(t, (f) async {
      await t.pumpWidget(
        f.host(withBack(f, f.page(value: f.model(description: long)))),
      );
      await showcasePump(t);
      expect(more(), findsOneWidget);
      await t.pumpWidget(f.host(withBack(f, f.page(value: f.model()))));
      await showcasePump(t);
      expect(more(), findsNothing);

      f.primary.requestFocus();
      await showcasePump(t);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await showcasePump(t);
      expect(f.back.hasFocus, isTrue);
    }, television: true);
  });

  test('text with no spaces still ends in a MORE that fits', () {
    const style = TextStyle(fontSize: 12);
    final head = synopsisHeadBeforeMore(
      text: '長' * 400,
      style: style,
      moreStyle: style,
      maxLines: 3,
      maxWidth: 300,
      textScaler: TextScaler.noScaling,
      textDirection: TextDirection.ltr,
    );
    expect(head, isNotNull);
    expect(head, isNotEmpty);
    final painter = TextPainter(
      text: TextSpan(text: '$head… MORE', style: style),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 300);
    expect(painter.didExceedMaxLines, isFalse);
    painter.dispose();
    expect(
      synopsisHeadBeforeMore(
        text: 'Short.',
        style: style,
        moreStyle: style,
        maxLines: 3,
        maxWidth: 300,
        textScaler: TextScaler.noScaling,
        textDirection: TextDirection.ltr,
      ),
      isNull,
    );
  });

  testWidgets('a description cut short by the addon gives way to the IMDb '
      'plot', (t) async {
    await showcaseCase(t, (f) async {
      const cut = 'Harry Da Souza knows where loyalties lie when forces col...';
      const plot =
          'Harry Da Souza knows where loyalties lie when forces collide.';
      final model = f.model(
        description: cut,
        extra: const ImdbEnrichment(plot: plot),
      );
      expect(model.synopsis, plot);
      expect(
        f
            .model(
              description: 'A complete line.',
              extra: const ImdbEnrichment(plot: plot),
            )
            .synopsis,
        'A complete line.',
      );
      expect(f.model(description: cut).synopsis, cut);
      // A cut plot is no better than the cut description it would replace.
      expect(
        f
            .model(
              description: cut,
              extra: const ImdbEnrichment(plot: 'Also cut short…'),
            )
            .synopsis,
        cut,
      );

      await t.pumpWidget(f.host(f.page(value: model)));
      await showcasePump(t);
      expect(find.text(plot), findsOneWidget);
    });
  });
}
