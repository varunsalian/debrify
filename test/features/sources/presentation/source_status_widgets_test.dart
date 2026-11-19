import 'package:debrify/features/sources/presentation/source_status_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('the searching strip adds the slow source line when given', (
    tester,
  ) async {
    await show(tester, const SourceSearchProgress());
    expect(find.text('Still searching sources…'), findsOneWidget);

    const detail = 'Looking through WebDAV · NAS… 3 folders checked';
    await show(tester, const SourceSearchProgress(detail: detail));
    expect(find.text('Still searching sources…'), findsOneWidget);
    expect(find.text(detail), findsOneWidget);
  });

  testWidgets('the first-load spinner explains what is still searched', (
    tester,
  ) async {
    await show(tester, const SourceLoadingIndicator());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Text), findsNothing);

    await show(
      tester,
      const SourceLoadingIndicator(detail: 'Looking through WebDAV · NAS…'),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Looking through WebDAV · NAS…'), findsOneWidget);
  });
}
