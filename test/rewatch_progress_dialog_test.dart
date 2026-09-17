import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/rewatch_progress_dialog.dart';

void main() {
  for (final movie in [true, false]) {
    testWidgets('rewatch confirmation and cancellation movie=$movie', (
      tester,
    ) async {
      var confirmed = false;
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await resetProgressForRewatch(
                    context,
                    id: 'tt001',
                    title: 'Example',
                    isMovie: movie,
                    onConfirmed: () => confirmed = true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text(movie ? 'Rewatch movie?' : 'Rewatch series?'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          movie
              ? 'permanently deletes its saved rating'
              : 'Season 1, Episode 1',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, false);
      expect(confirmed, false);
    });
  }
}
