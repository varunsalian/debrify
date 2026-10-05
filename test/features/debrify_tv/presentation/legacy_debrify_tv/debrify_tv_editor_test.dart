import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/debrify_tv_fixture.dart';

void main() {
  testWidgets('C7 R editor validation comma Enter and 1000 keyword cap', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.style = 'spotlight';
      await f.mount(t);
      f.spotlight.view.onAdd();
      await f.until(t, () => find.text('Save channel').evaluate().isNotEmpty);
      await f.tap(t, find.text('Save channel'));
      expect(find.text('Give the channel a name'), findsOneWidget);
      await t.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Channel name',
        ),
        'Editor original',
      );
      await f.tap(t, find.text('Save channel'));
      expect(find.text('Add at least one keyword'), findsOneWidget);
      await t.enterText(find.byType(EditableText).last, 'Alpha, beta, ALPHA');
      await t.pump();
      expect(find.text('Keywords (2/1000)'), findsOneWidget);
      expect(find.text('Alpha'), findsOneWidget);
      await t.enterText(find.byType(EditableText).last, 'gamma');
      t.widget<EditableText>(find.byType(EditableText).last).onSubmitted!(
        'gamma',
      );
      await t.pump();
      expect(find.text('Keywords (3/1000)'), findsOneWidget);
      await t.enterText(
        find.byType(EditableText).last,
        List.generate(1000, (i) => 'cap$i').join(','),
      );
      await t.pump();
      expect(find.text('Keywords (1000/1000)'), findsOneWidget);
      expect(
        find.text('You can add up to 1000 keywords per channel.'),
        findsOneWidget,
      );
      await f.tap(t, find.text('Cancel'));
      expect(f.spotlight.view.channels, hasLength(2));
    });
  });

  testWidgets(
    'C7 O removing keyword prunes cached pool and saves without network',
    (t) async {
      await debrifyTvCase(t, (f) async {
        f.style = 'spotlight';
        f.cacheKeywords = const [
          ['one'],
          ['two'],
        ];
        await f.mount(t);
        f.spotlight.view.onEdit(f.channels.first);
        await f.until(t, () => find.text('Save channel').evaluate().isNotEmpty);
        await f.tap(t, find.text('one'));
        expect(find.text('Keywords (2/1000)'), findsOneWidget);
        await f.tap(t, find.text('Save channel'));
        await f.until(
          t,
          () => find.textContaining('updated').evaluate().isNotEmpty,
        );
        expect(
          await t.runAsync(
            () =>
                DebrifyTvRepository.instance.fetchChannelKeywords('original-1'),
          ),
          ['two', 'three'],
        );
        final entry = await t.runAsync(
          () => DebrifyTvCacheService.getEntry('original-1'),
        );
        expect(entry!.torrents.map((e) => e.infohash), ['b' * 40]);
        expect(entry.normalizedKeywords, ['two', 'three']);
        expect(
          f.requests,
          isEmpty,
          reason: 'removed keyword pruning needs no warm-up',
        );
      });
    },
  );

  testWidgets('C7 O NSFW edit takes full warm-up and persists forced rebuild', (
    t,
  ) async {
    await debrifyTvCase(t, (f) async {
      f.style = 'spotlight';
      await f.mount(t);
      f.spotlight.view.onEdit(f.channels.first);
      await f.until(t, () => find.text('Save channel').evaluate().isNotEmpty);
      t.widget<SwitchRow>(find.byType(SwitchRow)).onChanged(true);
      await t.pump();
      await f.tap(t, find.text('Save channel'));
      await f.until(
        t,
        () => find
            .text('Channel cache rebuilt with updated NSFW filter.')
            .evaluate()
            .isNotEmpty,
      );
      expect(
        f.requests.where((r) => r.url.host == 'debrify-tv-original.test'),
        hasLength(3),
      );
      expect(
        (await t.runAsync(
          DebrifyTvRepository.instance.fetchAllChannels,
        ))!.first.avoidNsfw,
        isTrue,
      );
    });
  });
}
