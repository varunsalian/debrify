import 'package:debrify/screens/video_player/widgets/auto_sync_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(AutoSyncPillModel model) {
  return MaterialApp(
    home: Scaffold(body: Center(child: AutoSyncPill(model: model))),
  );
}

void main() {
  testWidgets('announce shows the keep-watching sentence', (tester) async {
    await tester.pumpWidget(
      _host(const AutoSyncPillModel(AutoSyncPillPhase.announce)),
    );
    expect(
      find.textContaining('Trying to auto-sync subtitles'),
      findsOneWidget,
    );
    expect(find.textContaining('keep watching'), findsOneWidget);
  });

  testWidgets('checking surfaces its status', (tester) async {
    await tester.pumpWidget(
      _host(const AutoSyncPillModel(AutoSyncPillPhase.checking)),
    );
    expect(find.text('CHECKING…'), findsOneWidget);
  });

  testWidgets('results are word-only', (tester) async {
    await tester.pumpWidget(
      _host(const AutoSyncPillModel(AutoSyncPillPhase.synced)),
    );
    expect(find.text('SUBTITLES SYNCED'), findsOneWidget);

    await tester.pumpWidget(
      _host(const AutoSyncPillModel(AutoSyncPillPhase.failed)),
    );
    await tester.pumpAndSettle();
    expect(find.text('LEFT UNCHANGED'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
  });
}
