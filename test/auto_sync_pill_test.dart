import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(AutoSyncPillModel model) {
  return MaterialApp(
    home: Scaffold(body: Center(child: AutoSyncPill(model: model))),
  );
}

void main() {
  testWidgets('listening shows the label and the countdown digits', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AutoSyncPillModel(AutoSyncPillPhase.listening, 67)),
    );
    expect(find.text('AUTO SYNC'), findsOneWidget);
    expect(find.text('67'), findsOneWidget);
  });

  testWidgets('checking swaps the label but keeps counting', (tester) async {
    await tester.pumpWidget(
      _host(const AutoSyncPillModel(AutoSyncPillPhase.checking, 45)),
    );
    expect(find.text('CHECKING…'), findsOneWidget);
    expect(find.text('45'), findsOneWidget);
  });

  testWidgets('results carry no digits', (tester) async {
    await tester.pumpWidget(
      _host(const AutoSyncPillModel(AutoSyncPillPhase.synced, 0)),
    );
    expect(find.text('SUBTITLES SYNCED'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(
      _host(const AutoSyncPillModel(AutoSyncPillPhase.failed, 0)),
    );
    await tester.pumpAndSettle();
    expect(find.text('LEFT UNCHANGED'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
