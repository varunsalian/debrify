import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Inspect the mounted public widget tree. Expected values are frozen contracts;
// neither source text nor the AST reader participates in these assertions.
void recordingTextProperties(
  WidgetTester tester,
  Finder finder, {
  required String reason,
  Color? color,
  double? size,
  FontWeight? weight,
  int? maxLines,
  TextOverflow? overflow,
  TextAlign? align,
  double? spacing,
  double? height,
  bool figures = false,
}) {
  final text = tester.widget<Text>(finder);
  final style = text.style;
  expect(
    {
      'maxLines': text.maxLines,
      'overflow': text.overflow,
      'textAlign': text.textAlign,
      'fontSize': style?.fontSize,
      'fontWeight': style?.fontWeight,
      'color': style?.color,
      'letterSpacing': style?.letterSpacing,
      'height': style?.height,
      'fontFeatures': style?.fontFeatures,
    },
    {
      'maxLines': maxLines,
      'overflow': overflow,
      'textAlign': align,
      'fontSize': size,
      'fontWeight': weight,
      'color': color,
      'letterSpacing': spacing,
      'height': height,
      'fontFeatures': figures ? const [FontFeature.tabularFigures()] : null,
    },
    reason: reason,
  );
}

Finder recordingText(Finder within, String data) => find.descendant(
  of: within,
  matching: find.byWidgetPredicate((w) => w is Text && w.data == data),
);

BoxDecoration recordingDecoration(WidgetTester tester, Finder within) =>
    tester
            .widgetList<Container>(
              find.descendant(of: within, matching: find.byType(Container)),
            )
            .firstWhere((w) => w.decoration is BoxDecoration)
            .decoration!
        as BoxDecoration;

void recordingBorder(
  WidgetTester tester,
  Finder within, {
  required String reason,
  required Color fill,
  required Color border,
  required double width,
  required double radius,
}) {
  final decoration = recordingDecoration(tester, within);
  expect(decoration.color, fill, reason: reason);
  expect(
    decoration.border,
    Border.all(color: border, width: width),
    reason: reason,
  );
  expect(
    decoration.borderRadius,
    BorderRadius.circular(radius),
    reason: reason,
  );
}
