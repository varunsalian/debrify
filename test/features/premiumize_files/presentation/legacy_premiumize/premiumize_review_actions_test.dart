import 'package:debrify/models/premiumize_transfer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/premiumize_files_fixture.dart';

Future<void> dismissReviewDialog(
  WidgetTester t,
  PremiumizeFixture f,
  String dismissal,
) async {
  expect(find.byType(AlertDialog), findsOneWidget);
  if (dismissal == 'Back') {
    await t.binding.handlePopRoute();
  } else {
    await t.tapAt(const Offset(8, 760));
  }
  await f.transitions(t);
  expect(find.byType(AlertDialog), findsNothing);
}

void main() {
  testWidgets(
    'active search hides selection toggle with populated listing and results',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      expect(find.byTooltip('Select items'), findsOneWidget);
      await t.tap(find.byTooltip('Search files'));
      await t.pump();
      expect(
        find.byTooltip('Select items'),
        findsNothing,
        reason: 'active search must hide the selection toggle',
      );
      await t.enterText(find.byType(TextField), 'Alpha');
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.member('isSearching') == false);
      expect(f.resultIds, ['hit']);
      expect(find.byTooltip('Select items'), findsNothing);
      await t.tap(find.byTooltip('Close search'));
      await t.pump();
      expect(find.byTooltip('Select items'), findsOneWidget);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'Alpha'}),
      ]);
    }),
  );
  testWidgets(
    'clear activate key removes populated results and returns focus to field',
    (t) => premiumizeCase(t, (f) async {
      f.searches['Alpha'] = [premiumizeFile('a2')];
      await f.mount(t);
      await t.tap(find.byTooltip('Search files'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Alpha');
      await t.pump(const Duration(milliseconds: 350));
      await f.until(t, () => f.member('isSearching') == false);
      expect(f.resultIds, ['a2']);
      expect(find.text('Video a2.mkv'), findsOneWidget);
      (f.member('searchClearFocusNode') as FocusNode).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(
        f.resultIds,
        isEmpty,
        reason: 'activate-key clear removes already populated results',
      );
      expect(
        find.text('Type to search your cloud'),
        findsOneWidget,
        reason:
            'cleared search remains active and shows its empty-query prompt',
      );
      expect(find.text('Video a2.mkv'), findsNothing);
      expect((f.member('searchController') as TextEditingController).text, '');
      expect((f.member('searchFocusNode') as FocusNode).hasFocus, isTrue);
      expect(f.log, [
        f.getRequest('folder/list'),
        f.getRequest('folder/search', {'q': 'Alpha'}),
      ]);
    }),
  );
  for (final dismissal in ['Back', 'barrier']) {
    testWidgets(
      'selected delete null dismissal keeps selection and makes no request $dismissal',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t);
        f.member('toggleSelectionMode')();
        f.member('toggleSelection')('a2');
        f.member('toggleSelection')('m5');
        final action = f.member('handleDeleteSelected')() as Future<void>;
        await f.transitions(t);
        await dismissReviewDialog(t, f, dismissal);
        await action;
        await t.pump();
        expect(f.log, [
          f.getRequest('folder/list'),
        ], reason: 'null selected-delete confirmation must not delete');
        expect(f.member('isSelectionMode'), isTrue);
        expect(f.member('selectedIds'), {'a2', 'm5'});
        expect(f.ids, ['z9', 'a2', 'm5']);
        expect(find.text('2 selected'), findsOneWidget);
      }),
    );
    testWidgets(
      'transfer delete null dismissal keeps rows and makes no request $dismissal',
      (t) => premiumizeCase(t, (f) async {
        await f.mount(t);
        await t.tap(find.text('Transfers'));
        await f.until(t, () => f.member('isLoadingTransfers') == false);
        final transfers = f.member('transfers') as List<PremiumizeTransfer>;
        final action =
            f.member('deleteTransfer')(transfers.first) as Future<void>;
        await f.transitions(t);
        await dismissReviewDialog(t, f, dismissal);
        await action;
        await t.pump();
        expect(f.log, [
          f.getRequest('folder/list'),
          f.getRequest('transfer/list'),
        ], reason: 'null transfer-delete confirmation must not delete');
        expect(
          (f.member('transfers') as List<PremiumizeTransfer>).map((v) => v.id),
          ['t9', 't2', 't5'],
        );
        expect(identical(f.member('transfers'), transfers), isTrue);
        expect(find.text('Finished fixture'), findsOneWidget);
      }),
    );
  }
}
