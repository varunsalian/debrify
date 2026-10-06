import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_catalogs_fixture.dart';

void main() {
  final net = CatalogNetwork();
  setUpAll(net.install);
  tearDownAll(() => net.client.close());
  for (final size in [
    const Size(1280, 800),
    const Size(600, 900),
    const Size(714, 900),
  ]) {
    testWidgets(
      'editor compact layout and Close initial focus at width ${size.width}',
      (t) => catalogCase(t, (f) async {
        await t.runAsync(() => f.seed([catalog()]));
        await f.mount(t, size: size);
        await f.editor(t);
        expect(catalogFocus('localCatalogEditorClose').hasPrimaryFocus, isTrue);
        final poster = find.byWidgetPredicate(
          (w) => w is ClipRRect && w.child is Container,
        );
        final widths = t
            .widgetList<ClipRRect>(poster)
            .map((w) => (w.child as Container).constraints?.maxWidth)
            .whereType<double>()
            .toList();
        expect(
          widths,
          contains(size.width == 1280 ? 60.0 : 52.0),
          reason: 'content widths 880, 536, 650 use the 700 boundary',
        );
        await keyCatalog(t, LogicalKeyboardKey.arrowDown);
        expect(
          catalogFocus('localCatalogEditorRemove0').hasPrimaryFocus,
          isTrue,
        );
        await keyCatalog(t, LogicalKeyboardKey.arrowUp);
        expect(catalogFocus('localCatalogEditorClose').hasPrimaryFocus, isTrue);
        await keyCatalog(t, LogicalKeyboardKey.select);
        expect(f.result, isFalse);
      }),
    );
  }
  testWidgets(
    'editor not found, loading and Back return unchanged false',
    (t) => catalogCase(t, (f) async {
      await f.mount(t);
      StremioTvLocalCatalogEditorDialog.show(
        f.context,
        catalogId: 'gone',
        catalogType: 'movie',
      ).then((v) => f.result = v);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await pumpCatalog(t);
      expect(find.textContaining('could not be found'), findsOneWidget);
      await t.binding.handlePopRoute();
      await pumpCatalog(t);
      expect(f.result, isFalse);
    }),
  );
  testWidgets(
    'editor cancel preserves items; removing middle restores next row then previous',
    (t) => catalogCase(t, (f) async {
      await t.runAsync(() => f.seed([catalog(count: 4)]));
      await f.mount(t);
      await f.editor(t);
      await removeCatalogItem(t, 1, confirm: false);
      expect((await t.runAsync(f.rows))!.single['items'], hasLength(4));
      await removeCatalogItem(t, 1);
      expect((await t.runAsync(f.rows))!.single['items'], [
        containsPair('id', 'tt0'),
        containsPair('id', 'tt2'),
        containsPair('id', 'tt3'),
      ]);
      expect(
        catalogFocus('localCatalogEditorRemove1').hasPrimaryFocus,
        isTrue,
        reason: 'focus successor at same index after removal',
      );
      await removeCatalogItem(t, 2);
      expect(
        catalogFocus('localCatalogEditorRemove1').hasPrimaryFocus,
        isTrue,
        reason: 'last row removal focuses predecessor',
      );
      await focusCatalog(t, 'localCatalogEditorClose');
      await keyCatalog(t, LogicalKeyboardKey.goBack);
      expect(f.result, isTrue);
    }),
  );
  testWidgets(
    'editor last item deletes catalog and returns true',
    (t) => catalogCase(t, (f) async {
      await t.runAsync(() => f.seed([catalog(count: 1)]));
      await f.mount(t);
      await f.editor(t);
      await removeCatalogItem(t, 0);
      expect(await t.runAsync(f.rows), isEmpty);
      expect(f.result, isTrue);
      expect(
        find.text('Channel removed because it no longer has any items'),
        findsOneWidget,
      );
    }),
  );
  for (final changed in [false, true]) {
    testWidgets(
      'editor barrier returns recorded changed=$changed',
      (t) => catalogCase(t, (f) async {
        await t.runAsync(() => f.seed([catalog()]));
        await f.mount(t);
        await f.editor(t);
        if (changed) await removeCatalogItem(t, 0);
        await t.tapAt(const Offset(8, 8));
        await pumpCatalog(t);
        expect(f.result, changed);
      }),
    );
  }
  testWidgets(
    'editor failed update leaves visible and stored items and shows red snackbar',
    (t) => catalogCase(t, (f) async {
      await t.runAsync(() => f.seed([catalog()]));
      await f.mount(t);
      await f.editor(t);
      await t.runAsync(
        () => StremioCatalogStorage.removeStremioTvLocalCatalog('cat'),
      );
      await removeCatalogItem(t, 0);
      expect(find.text('Local catalog could not be updated'), findsOneWidget);
      expect(
        t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
        Colors.red.shade700,
      );
      expect(find.text('Item 0'), findsOneWidget);
      expect(await t.runAsync(f.rows), isEmpty);
      expect(f.result, 'pending');
    }),
  );
  testWidgets(
    'editor long D-pad chain scrolls row into view and system Back returns changed',
    (t) => catalogCase(t, (f) async {
      await t.runAsync(() => f.seed([catalog(count: 18)]));
      await f.mount(t);
      await f.editor(t);
      for (var i = 0; i < 12; i++) {
        await keyCatalog(t, LogicalKeyboardKey.arrowDown);
      }
      expect(
        catalogFocus('localCatalogEditorRemove11').hasPrimaryFocus,
        isTrue,
      );
      final list = t.widget<ListView>(find.byType(ListView));
      expect(list.controller!.offset, greaterThan(0));
      await t.binding.handlePopRoute();
      await pumpCatalog(t);
      expect(f.result, isFalse);
    }),
  );

  testWidgets(
    'review editor D-pad chain Close row0 row1 and back consumes every key',
    (t) => catalogCase(t, (f) async {
      await t.runAsync(() => f.seed([catalog()]));
      await f.mount(t);
      await f.editor(t);
      final handled = <KeyEventResult>[];
      for (final label in [
        'localCatalogEditorClose',
        'localCatalogEditorRemove0',
        'localCatalogEditorRemove1',
      ]) {
        final node = catalogFocus(label);
        final original = node.onKeyEvent!;
        node.onKeyEvent = (n, event) {
          final result = original(n, event);
          if (event is KeyDownEvent) handled.add(result);
          return result;
        };
      }
      for (final step in [
        (LogicalKeyboardKey.arrowDown, 'localCatalogEditorRemove0'),
        (LogicalKeyboardKey.arrowDown, 'localCatalogEditorRemove1'),
        (LogicalKeyboardKey.arrowUp, 'localCatalogEditorRemove0'),
        (LogicalKeyboardKey.arrowUp, 'localCatalogEditorClose'),
      ]) {
        await keyCatalog(t, step.$1);
        expect(handled, isNotEmpty);
        expect(
          handled.last,
          KeyEventResult.handled,
          reason: 'the custom D-pad handler consumes ${step.$1.keyLabel}',
        );
        expect(catalogFocus(step.$2).hasPrimaryFocus, isTrue);
      }
    }),
  );
  testWidgets(
    'review editor activates the selected row item in its confirm',
    (t) => catalogCase(t, (f) async {
      final before = catalog();
      await t.runAsync(() => f.seed([before]));
      await f.mount(t);
      await f.editor(t);
      await focusCatalog(t, 'localCatalogEditorRemove1');
      await keyCatalog(t, LogicalKeyboardKey.select);
      expect(
        find.text('Remove "Item 1" from this local channel?'),
        findsOneWidget,
      );
      expect(
        find.text('Remove "Item 2" from this local channel?'),
        findsNothing,
      );
      await t.tap(find.text('Cancel'));
      await pumpCatalog(t);
      expect(await t.runAsync(f.rows), [before]);
    }),
  );
  testWidgets(
    'review editor persists exact order and last-row removal focuses new last',
    (t) => catalogCase(t, (f) async {
      final before = catalog(count: 4, meta: {'marker': 'preserved'});
      final items = before['items'] as List;
      await t.runAsync(() => f.seed([before]));
      await f.mount(t);
      await f.editor(t);
      await removeCatalogItem(t, 1);
      expect(await t.runAsync(f.rows), [
        {
          ...before,
          'items': [items[0], items[2], items[3]],
        },
      ]);
      await removeCatalogItem(t, 2);
      expect(await t.runAsync(f.rows), [
        {
          ...before,
          'items': [items[0], items[2]],
        },
      ]);
      expect(
        catalogFocus('localCatalogEditorRemove1').hasPrimaryFocus,
        isTrue,
        reason: 'removed index equals new length; focus the new last row',
      );
    }),
  );
  for (final changed in [false, true]) {
    testWidgets(
      'review editor system Back returns changed=$changed',
      (t) => catalogCase(t, (f) async {
        final before = catalog();
        await t.runAsync(() => f.seed([before]));
        await f.mount(t);
        await f.editor(t);
        if (changed) {
          await removeCatalogItem(t, 1);
          final items = before['items'] as List;
          expect(await t.runAsync(f.rows), [
            {
              ...before,
              'items': [items[0], items[2]],
            },
          ]);
        }
        await t.binding.handlePopRoute();
        await pumpCatalog(t);
        expect(f.result, changed);
      }),
    );
  }
}
