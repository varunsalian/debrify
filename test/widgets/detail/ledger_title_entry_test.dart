import 'package:debrify/features/ledger/application/ledger_sign_in_controller.dart';
import 'package:debrify/features/ledger/application/ledger_title_controller.dart';
import 'package:debrify/features/ledger/models/ledger_brand.dart';
import 'package:debrify/features/ledger/models/ledger_title.dart';
import 'package:debrify/features/merged_detail/presentation/merged_sheet_switch_row.dart';
import 'package:debrify/widgets/detail/ledger_title_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements LedgerTitleGateway {
  @override
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  bool connected = true;
  LedgerTitleStatus held = const LedgerTitleStatus();
  final List<String> sent = [];

  @override
  bool supports(String imdbId) => true;

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<LedgerTitleStatus?> status(LedgerTitleKey key) async => held;

  Future<bool> _write(String name, LedgerTitleStatus next) async {
    sent.add(name);
    held = next;
    return true;
  }

  @override
  Future<bool> setPlanned(LedgerTitleKey key, bool planned) => _write(
    'planned:$planned',
    LedgerTitleStatus(planned: planned, rating: held.rating),
  );

  @override
  Future<bool> setCompleted(LedgerTitleKey key, bool completed) => _write(
    'completed:$completed',
    LedgerTitleStatus(completed: completed, started: completed),
  );

  @override
  Future<bool> setDropped(LedgerTitleKey key, bool dropped) =>
      _write('dropped:$dropped', LedgerTitleStatus(dropped: dropped));

  @override
  Future<bool> rate(LedgerTitleKey key, int? rating) =>
      _write('rate:$rating', LedgerTitleStatus(rating: rating));

  @override
  Future<bool> clearProgress(LedgerTitleKey key) =>
      _write('clear', const LedgerTitleStatus());
}

const LedgerTitleKey _key = (imdbId: 'tt2707408', contentType: 'series');

void main() {
  late _Gateway gateway;
  late int watchedChanges;

  setUp(() {
    gateway = _Gateway();
    watchedChanges = 0;
  });

  Widget entry({bool television = false}) => MaterialApp(
    home: Scaffold(
      body: LedgerTitleEntry(
        titleKey: _key,
        title: 'Narcos',
        isTelevision: television,
        onWatchedChanged: () => watchedChanges++,
        builder: (context, status, onTap) =>
            TextButton(onPressed: onTap, child: Text('pill:${status.label}')),
      ),
    ),
  );

  Future<void> pump(WidgetTester tester, {bool television = false}) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerTitleGatewayProvider.overrideWithValue(gateway),
          ledgerSignInScopeProvider.overrideWithValue(() => 'profile'),
        ],
        child: entry(television: television),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool switchOn(WidgetTester tester, String label) => tester
      .widget<MergedSheetSwitchRow>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(MergedSheetSwitchRow),
        ),
      )
      .value;

  testWidgets('no button while signed out or outside the app scope', (
    tester,
  ) async {
    gateway.connected = false;
    await pump(tester);
    expect(find.textContaining('pill:'), findsNothing);

    await tester.pumpWidget(entry());
    await tester.pumpAndSettle();
    expect(find.textContaining('pill:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet offers only the three statuses, rating and clear', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('pill:Not tracked'));
    await tester.pumpAndSettle();

    expect(find.text(kLedgerDisplayName), findsOneWidget);
    expect(find.text('Narcos'), findsOneWidget);
    expect(find.byType(MergedSheetSwitchRow), findsNWidgets(3));
    for (final label in ['Plan to Watch', 'Completed', 'Dropped']) {
      expect(switchOn(tester, label), isFalse);
    }
    expect(find.text('Watching'), findsNothing);
    expect(find.text('On Hold'), findsNothing);
    expect(find.text('10'), findsOneWidget);
    expect(
      find.text('Clear watch progress on $kLedgerDisplayName'),
      findsOneWidget,
    );
  });

  testWidgets('each row sends its change, stays open and updates the button', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('pill:Not tracked'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plan to Watch'));
    await tester.pumpAndSettle();
    expect(switchOn(tester, 'Plan to Watch'), isTrue);
    expect(find.text('pill:Plan to Watch'), findsOneWidget);
    expect(watchedChanges, 0);

    await tester.tap(find.text('7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dropped'));
    await tester.pumpAndSettle();
    expect(switchOn(tester, 'Dropped'), isTrue);

    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(switchOn(tester, 'Completed'), isTrue);
    expect(watchedChanges, 1);

    // Turning Completed off removes the plays.
    await tester.tap(find.text('Completed'));
    await tester.pumpAndSettle();
    expect(switchOn(tester, 'Completed'), isFalse);

    await tester.tap(find.text('Clear watch progress on $kLedgerDisplayName'));
    await tester.pumpAndSettle();
    expect(watchedChanges, 3);
    expect(find.byType(MergedSheetSwitchRow), findsNWidgets(3));
    expect(gateway.sent, [
      'planned:true',
      'rate:7',
      'dropped:true',
      'completed:true',
      'completed:false',
      'clear',
    ]);
  });

  testWidgets('on TV the sheet starts on the first row and Back closes it', (
    tester,
  ) async {
    await pump(tester, television: true);
    await tester.tap(find.text('pill:Not tracked'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(gateway.sent, ['planned:true']);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(gateway.sent, ['planned:true', 'completed:true']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MergedSheetSwitchRow), findsNothing);
    expect(find.text('pill:Completed'), findsOneWidget);
  });
}
