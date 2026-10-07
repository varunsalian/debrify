import 'package:flutter_test/flutter_test.dart';
import '../../../../support/premiumize_files_fixture.dart';

void main() {
  for (final prefix in [
    'Story Season',
    'Story Chapter',
    'Chapter',
    'Story Episode',
    'Story Part',
    '',
    'Volume_',
  ]) {
    testWidgets(
      'Sort orders two and ten folders using pattern $prefix',
      (t) => premiumizeCase(t, (f) async {
        final ten = prefix.isEmpty ? '10. Story' : '$prefix 10';
        final two = prefix.isEmpty ? '2. Story' : '$prefix 2';
        // Embedded labels distinguish the unanchored named patterns from
        // the final anchored letters-plus-number fallback.
        f.pages['z9'] = [
          premiumizeFile('m5', name: ten, folder: true),
          premiumizeFile('a2', name: two, folder: true),
        ];
        await f.mount(t);
        f.member('navigateIntoFolder')(f.items.first);
        await f.until(t, () => f.member('isLoading') == false);
        expect(f.ids, ['m5', 'a2']);
        f.member('setViewMode')(f.member('sortedMode'));
        await t.pump();
        expect(f.ids, [
          'a2',
          'm5',
        ], reason: 'folder numeric pattern must sort 2 before 10');
        expect(f.member('extractSeasonNumber')(two), 2);
        expect(f.member('extractSeasonNumber')(ten), 10);
        expect(f.log, [
          f.getRequest('folder/list'),
          f.getRequest('folder/list', {'id': 'z9'}),
        ]);
      }),
    );
  }
  testWidgets(
    'date formats minutes hours days and seven days plus twelve hours as date',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      // DateTime.now has no injected production clock. Wide margins keep
      // these synchronous observations away from minute/hour/day cutoffs.
      final now = DateTime.now();
      final minutes = now.subtract(const Duration(minutes: 30, seconds: 30));
      final hours = now.subtract(const Duration(hours: 5, minutes: 30));
      final days = now.subtract(const Duration(days: 3, hours: 12));
      final old = now.subtract(const Duration(days: 7, hours: 12));
      int seconds(DateTime date) => date.millisecondsSinceEpoch ~/ 1000;
      expect(f.member('formatUnixDate')(seconds(minutes)), '30m ago');
      expect(f.member('formatUnixDate')(seconds(hours)), '5h ago');
      expect(f.member('formatUnixDate')(seconds(days)), '3d ago');
      expect(
        f.member('formatUnixDate')(seconds(old)),
        [old.month, old.day, old.year].join('/'),
        reason: 'seven days plus twelve hours uses calendar date',
      );
      expect(f.log, [f.getRequest('folder/list')]);
    }),
  );
}
