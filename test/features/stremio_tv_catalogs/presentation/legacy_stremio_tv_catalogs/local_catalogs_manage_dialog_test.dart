import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/stremio_tv_catalogs_fixture.dart';

void main() {
  final net = CatalogNetwork();
  setUpAll(net.install);
  tearDownAll(() => net.client.close());
  setUp(net.reset);
  testWidgets(
    'manage loading empty and Close false; statics center the dialog',
    (t) => catalogCase(t, (f) async {
      await f.mount(t);
      StremioTvLocalCatalogsDialog.show(f.context).then((v) => f.result = v);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await pumpCatalog(t);
      expect(
        find.text('No local catalogs yet.\nUse the menu to import catalogs.'),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: find.byType(StremioTvLocalCatalogsDialog),
          matching: find.byType(Center),
        ),
        findsWidgets,
      );
      await t.tap(find.byTooltip('Close'));
      await pumpCatalog(t);
      expect(f.result, isFalse);
    }),
  );
  testWidgets(
    'manage subtitles only sourced rows refresh; delete cancel then confirm and Close true',
    (t) => catalogCase(t, (f) async {
      await t.runAsync(
        () => f.seed([
          catalog(id: 'trakt', meta: {'traktSource': 'watchlist'}),
          catalog(id: 'mdb', name: 'MDB', meta: {'mdblistListId': 42}),
          catalog(id: 'plain', name: 'Plain'),
        ]),
      );
      await f.mount(t);
      await f.manage(t);
      expect(find.text('3 items · Trakt'), findsOneWidget);
      expect(find.text('3 items · MDBList'), findsOneWidget);
      for (final row in {
        'Cinema': '3 items · Trakt',
        'MDB': '3 items · MDBList',
        'Plain': '3 items',
      }.entries) {
        final tile = t.widget<ListTile>(find.widgetWithText(ListTile, row.key));
        expect(
          (tile.subtitle! as Text).data,
          row.value,
          reason: '${row.key} source label',
        );
      }
      expect(find.byIcon(Icons.refresh_rounded), findsNWidgets(2));
      await focusCatalog(t, 'close');
      await keyCatalog(t, LogicalKeyboardKey.arrowDown);
      expect(catalogFocus('del0').hasPrimaryFocus, isTrue);
      await keyCatalog(t, LogicalKeyboardKey.select);
      expect(find.text('Remove "Cinema" and all its items?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await pumpCatalog(t);
      expect(await t.runAsync(f.rows), hasLength(3));
      await focusCatalog(t, 'del0');
      await keyCatalog(t, LogicalKeyboardKey.select);
      await t.tap(find.text('Delete'));
      await pumpCatalog(t);
      expect((await t.runAsync(f.rows))!.map((r) => r['id']), ['mdb', 'plain']);
      await focusCatalog(t, 'close');
      await keyCatalog(t, LogicalKeyboardKey.select);
      expect(f.result, isTrue);
    }),
  );
  testWidgets(
    'manage D-pad uses 56 pixel scroll offsets and leaves Close offset alone',
    (t) => catalogCase(t, (f) async {
      await t.runAsync(
        () => f.seed([
          for (var i = 0; i < 30; i++) catalog(id: 'c$i', name: 'Catalog $i'),
        ]),
      );
      await f.mount(t, size: const Size(1280, 800));
      await f.manage(t);
      await focusCatalog(t, 'close');
      for (var i = 0; i < 6; i++) {
        await keyCatalog(t, LogicalKeyboardKey.arrowDown);
      }
      final list = t.widget<ListView>(find.byType(ListView));
      expect(list.controller!.offset, 280.0);
      expect(catalogFocus('del5').hasPrimaryFocus, isTrue);
      await keyCatalog(t, LogicalKeyboardKey.arrowUp);
      expect(list.controller!.offset, 224.0);
    }),
  );
  testWidgets(
    'manage refresh disables every other refresh, row spinner, success reload and Close true',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        await t.runAsync(f.auth);
        await t.runAsync(
          () => f.seed([
            catalog(id: 'a', meta: {'traktSource': 'watchlist'}),
            catalog(
              id: 'b',
              name: 'Second',
              meta: {'traktSource': 'watchlist'},
            ),
          ]),
        );
        final held = Completer<http.Response>();
        net.handler = (r) async => held.future;
        await f.mount(t);
        await f.manage(t);
        await t.tap(find.byTooltip('Refresh from Trakt').first);
        await pumpCatalog(t, rounds: 2);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
          t
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Refresh from Trakt',
                ),
              )
              .onPressed,
          isNull,
          reason: 'no second refresh while first is pending',
        );
        held.complete(response([traktItem('tt99')]));
        await pumpCatalog(t);
        expect(find.text('"Cinema" refreshed'), findsOneWidget);
        expect(find.text('2 items · Trakt'), findsOneWidget);
        expect((await t.runAsync(f.rows))!.first['items'], hasLength(2));
        await t.tap(find.byTooltip('Close'));
        await pumpCatalog(t);
        expect(f.result, isTrue);
      }),
    ),
  );
  testWidgets(
    'manage Trakt refresh failure red snackbar and unchanged Close false',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        await t.runAsync(f.auth);
        await t.runAsync(
          () => f.seed([
            catalog(meta: {'traktSource': 'watchlist'}),
          ]),
        );
        await f.mount(t);
        await f.manage(t);
        await t.tap(find.byTooltip('Refresh from Trakt'));
        await pumpCatalog(t);
        expect(
          find.text('Refresh failed: No items found in list'),
          findsOneWidget,
        );
        expect(
          t.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
          Colors.red.shade700,
        );
        await t.tap(find.byTooltip('Close'));
        await pumpCatalog(t);
        expect(f.result, isFalse);
      }),
    ),
  );
  testWidgets(
    'manage MDB refresh persists filtered items, success and failure snackbars',
    (t) => catalogCase(t, (f) async {
      await t.runAsync(f.auth);
      await t.runAsync(
        () => f.seed([
          catalog(meta: {'mdblistListId': 42}),
        ]),
      );
      net.handler = (r) async => response(mdblistItems);
      await f.mount(t);
      await f.manage(t);
      await t.tap(find.byTooltip('Refresh from MDBList'));
      await pumpCatalog(t);
      expect(find.text('"Cinema" refreshed'), findsOneWidget);
      expect(find.text('1 items · MDBList'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
      await t.pump(const Duration(milliseconds: 300));
      net.handler = (r) async => response({}, status: 403);
      await t.tap(find.byTooltip('Refresh from MDBList'));
      await pumpCatalog(t);
      expect(
        find.text('Refresh failed: Failed to refresh from MDBList'),
        findsOneWidget,
      );
    }),
  );
  for (final cap in [20 * 1024 * 1024, 20 * 1024 * 1024 + 1]) {
    testWidgets(
      'file picker size $cap boundary and exact picker flags',
      (t) => catalogCase(t, (f) async {
        await f.mount(t);
        f.picker.file(
          'Cinema.JSON',
          size: cap,
          bytes: utf8.encode(jsonEncode([traktItem('tt1')])),
        );
        final result = await t.runAsync(
          () => StremioTvLocalCatalogsDialog.importFromFile(f.context),
        );
        await pumpCatalog(t);
        expect(f.picker.type, FileType.any);
        expect(f.picker.withData, isTrue);
        if (cap == 20 * 1024 * 1024) {
          expect(result, isTrue);
          expect((await t.runAsync(f.rows))!.single['name'], 'Cinema');
          expect(find.text('Catalog imported'), findsOneWidget);
          expect(
            t.widget<SnackBar>(find.byType(SnackBar)).duration,
            const Duration(seconds: 2),
          );
        } else {
          expect(result, isFalse);
          expect(
            find.text('That file is too large to be a catalog'),
            findsOneWidget,
          );
          expect(
            t.widget<SnackBar>(find.byType(SnackBar)).duration,
            const Duration(seconds: 4),
          );
          expect(await t.runAsync(f.rows), isEmpty);
        }
      }),
    );
  }
  for (final branch in [
    'cancel',
    'empty',
    'null bytes',
    'invalid',
    'exception',
  ]) {
    testWidgets(
      'file import $branch returns false with exact snackbar policy',
      (t) => catalogCase(t, (f) async {
        await f.mount(t);
        if (branch == 'empty') f.picker.result = FilePickerResult([]);
        if (branch == 'null bytes') f.picker.file('Null.json');
        if (branch == 'invalid') {
          f.picker.file('Bad.json', bytes: utf8.encode('{}'));
        }
        if (branch == 'exception') f.picker.error = StateError('picker failed');
        expect(
          await t.runAsync(
            () => StremioTvLocalCatalogsDialog.importFromFile(f.context),
          ),
          isFalse,
        );
        await pumpCatalog(t);
        final message = switch (branch) {
          'null bytes' => 'Could not read file',
          'invalid' => 'Missing "name" field',
          'exception' => 'Failed: Bad state: picker failed',
          _ => null,
        };
        if (message != null) {
          expect(find.text(message), findsOneWidget);
          final bar = t.widget<SnackBar>(find.byType(SnackBar));
          expect(bar.duration, const Duration(seconds: 4));
          expect(bar.backgroundColor, Colors.red.shade700);
        } else {
          expect(find.byType(SnackBar), findsNothing);
        }
        expect(await t.runAsync(f.rows), isEmpty);
      }),
    );
  }
}
