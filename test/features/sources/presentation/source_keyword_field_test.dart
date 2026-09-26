import 'package:debrify/features/sources/presentation/source_keyword_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final submitByButton in [true, false]) {
    testWidgets(
      'keyword header forwards exact input via button: $submitByButton',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final submitted = <String>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SourceKeywordField(
                scheme: ColorScheme.fromSeed(seedColor: Colors.blue),
                controller: controller,
                onSubmitted: submitted.add,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '  Exact QUERY  ');
        if (submitByButton) {
          await tester.tap(find.byTooltip('Search'));
        } else {
          await tester.testTextInput.receiveAction(TextInputAction.search);
        }
        await tester.pump();
        expect(submitted, ['  Exact QUERY  ']);
        expect(controller.text, '  Exact QUERY  ');
        await tester.pumpWidget(const SizedBox());
        // The field borrows the view's controller and must leave it usable.
        controller.text = 'next query';
        expect(controller.text, 'next query');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
