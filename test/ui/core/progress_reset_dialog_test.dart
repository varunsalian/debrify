import 'dart:async';

import 'package:debrify/ui/core/progress_reset_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    'success',
    'partial',
    'throw',
    'covered',
    'retired',
    'cancel',
    'retired-confirm',
    'unmount',
  ]) {
    testWidgets('reset dialog owns loader: $scenario', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final operation = Completer<List<String>>();
      var current = true, calls = 0;
      Future<void>? pending;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(
            dialogTheme: const DialogThemeData(barrierColor: Color(0x99223344)),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  pending = runProgressResetDialog(
                    context: context,
                    isCurrent: () => current,
                    confirmation: (ctx) => AlertDialog(
                      title: const Text('Reset?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Confirm'),
                        ),
                      ],
                    ),
                    reset: () {
                      calls++;
                      return operation.future;
                    },
                    message: (failures) => failures.isEmpty ? 'Done' : 'Failed',
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
      if (scenario == 'cancel') {
        navigator.currentState!.pop(false);
      } else {
        if (scenario == 'retired-confirm') current = false;
        await tester.tap(find.text('Confirm'));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      if (scenario == 'cancel' || scenario == 'retired-confirm') {
        await pending;
        expect(calls, 0);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        return;
      }
      expect(calls, 1);
      expect(find.text('Clearing watch progress…'), findsOneWidget);
      expect(
        tester.widget<ModalBarrier>(find.byType(ModalBarrier).last).color,
        const Color(0x99223344),
      );
      if (scenario == 'covered') {
        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('New page')),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
      if (scenario == 'retired') current = false;
      if (scenario == 'unmount') await tester.pumpWidget(const SizedBox());
      if (scenario == 'throw') {
        final check = expectLater(pending, throwsStateError);
        operation.completeError(StateError('fixture failure'));
        await check;
      } else {
        operation.complete(scenario == 'partial' ? ['provider'] : []);
        await pending;
      }
      await tester.pumpAndSettle();
      expect(
        find.text('Clearing watch progress…', skipOffstage: false),
        findsNothing,
      );
      if (scenario == 'covered') {
        expect(find.text('New page'), findsOneWidget);
        navigator.currentState!.pop();
        await tester.pumpAndSettle();
      }
      expect(
        find.text('Done'),
        ['retired', 'unmount', 'throw', 'partial'].contains(scenario)
            ? findsNothing
            : findsOneWidget,
      );
      if (scenario == 'partial') expect(find.text('Failed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
