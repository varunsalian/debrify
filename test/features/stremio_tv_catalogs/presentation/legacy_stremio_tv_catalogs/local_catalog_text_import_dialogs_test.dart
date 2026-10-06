import 'dart:async';
import 'dart:convert';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/stremio_tv_catalogs_fixture.dart';

TextField field(WidgetTester t, int i) =>
    t.widgetList<TextField>(find.byType(TextField)).toList()[i];
Future<void> input(WidgetTester t, int i, String text) async {
  field(t, i).controller!.text = text;
  await t.pump();
}

void main() {
  final net = CatalogNetwork();
  setUpAll(net.install);
  tearDownAll(() => net.client.close());
  setUp(net.reset);
  for (final kind in ['URL', 'JSON']) {
    final show = kind == 'URL'
        ? StremioTvLocalCatalogsDialog.importFromUrl
        : StremioTvLocalCatalogsDialog.importFromJson;
    testWidgets(
      '$kind empty input, importer error and cancel false',
      (t) => net.run(
        () => catalogCase(t, (f) async {
          await f.mount(t);
          await f.dialog(t, show);
          await t.tap(find.text('Import'));
          await pumpCatalog(t);
          expect(
            find.text(kind == 'URL' ? 'Enter a URL' : 'Paste JSON content'),
            findsOneWidget,
          );
          if (kind == 'URL') {
            await input(t, 1, 'not a url');
            await t.tap(find.text('Import'));
            await pumpCatalog(t);
            expect(find.text('Invalid URL'), findsOneWidget);
            net.handler = (r) async => response({});
            await input(t, 1, 'https://catalog.test/x');
          } else {
            await input(t, 1, '{}');
          }
          await t.tap(find.text('Import'));
          await pumpCatalog(t);
          expect(find.text('Missing "name" field'), findsOneWidget);
          await t.tap(find.text('Cancel'));
          await pumpCatalog(t);
          expect(f.result, isFalse);
          expect(await t.runAsync(f.rows), isEmpty);
        }),
      ),
    );
    testWidgets(
      '$kind forwards name and success returns true and saves split',
      (t) => net.run(
        () => catalogCase(t, (f) async {
          await f.mount(t);
          await f.dialog(t, show);
          await input(t, 0, ' Named ');
          if (kind == 'URL') {
            net.handler = (r) async => response(mixedTrakt);
            await input(t, 1, '  https://catalog.test/list.json  ');
          } else {
            await input(t, 1, '  ${jsonEncode(mixedTrakt)}  ');
          }
          await t.tap(find.text('Import'));
          await pumpCatalog(t);
          expect(f.result, isTrue);
          expect((await t.runAsync(f.rows))!.map((r) => r['name']), [
            'Named — Movies',
            'Named — Series',
          ]);
          if (kind == 'URL') {
            expect(net.requests, hasLength(1));
            expect(net.requests.single.method, 'GET');
            expect(
              net.requests.single.url.toString(),
              'https://catalog.test/list.json',
            );
          }
        }),
      ),
    );
  }
  testWidgets(
    'URL exact HTTP status error and exception failure text',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
        await input(t, 1, 'https://catalog.test/fail');
        net.handler = (r) async => response({}, status: 418);
        await t.tap(find.text('Import'));
        await pumpCatalog(t);
        expect(find.text('HTTP 418'), findsOneWidget);
        net.handler = (r) async => throw StateError('fixture failure');
        await t.tap(find.text('Import'));
        await pumpCatalog(t);
        expect(find.text('Failed: Bad state: fixture failure'), findsOneWidget);
      }),
    ),
  );
  testWidgets(
    'URL times out at 15 seconds, disables Import and issues only one GET',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        final held = Completer<http.Response>();
        net.handler = (r) => held.future;
        try {
          await f.mount(t);
          await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
          await input(t, 1, 'https://catalog.test/held');
          await t.tap(find.text('Import'));
          await pumpCatalog(t, rounds: 1);
          expect(
            t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          expect(net.requests, hasLength(1));
          await t.pump(const Duration(seconds: 14));
          expect(find.text('Request timed out'), findsNothing);
          await t.pump(const Duration(seconds: 1));
          await t.pump();
          expect(
            find.text('Request timed out'),
            findsOneWidget,
            reason: '15 second observable timeout',
          );
          expect(
            t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNotNull,
          );
        } finally {
          held.complete(response(catalog()));
          await pumpCatalog(t, rounds: 1);
        }
      }),
    ),
  );
  testWidgets(
    'URL submitting the URL field starts import',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        net.handler = (r) async => response(catalog());
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
        await input(t, 1, 'https://catalog.test/submit');
        field(t, 1).onSubmitted!('ignored');
        await pumpCatalog(t);
        expect(f.result, isTrue);
        expect(net.requests, hasLength(1));
      }),
    ),
  );
  for (final key in [
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.goBack,
    LogicalKeyboardKey.browserBack,
  ]) {
    testWidgets(
      'URL TV shell Back ${key.keyLabel} hops to Cancel without popping',
      (t) => catalogCase(t, (f) async {
        f.tv(true);
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
        await focusCatalog(t, 'stremio-import-url-url');
        await keyCatalog(t, key);
        expect(
          catalogFocus('stremio-import-url-cancel').hasPrimaryFocus,
          isTrue,
        );
        expect(f.result, 'pending');
      }),
    );
  }
  testWidgets(
    'URL TV editing consumes Back then shell Back reaches Cancel',
    (t) => catalogCase(t, (f) async {
      f.tv(true);
      await f.mount(t);
      await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
      await focusCatalog(t, 'stremio-import-url-url');
      await keyCatalog(t, LogicalKeyboardKey.select);
      final state = t.state<TvTextFieldState>(find.byType(TvTextField).last);
      expect(state.debugHasKeyboardOverlay, isTrue);
      await keyCatalog(t, LogicalKeyboardKey.escape);
      expect(state.debugHasKeyboardOverlay, isFalse);
      expect(catalogFocus('stremio-import-url-url').hasFocus, isTrue);
      expect(f.result, 'pending');
      await keyCatalog(t, LogicalKeyboardKey.escape);
      expect(catalogFocus('stremio-import-url-cancel').hasPrimaryFocus, isTrue);
    }),
  );
  testWidgets(
    'URL non-TV uses actual TextFields without TV shell editing overlay',
    (t) => catalogCase(t, (f) async {
      f.tv(false);
      await f.mount(t);
      await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
      expect(field(t, 1).focusNode, catalogFocus('stremio-import-url-url'));
      expect(
        t
            .state<TvTextFieldState>(find.byType(TvTextField).last)
            .debugHasKeyboardOverlay,
        isFalse,
      );
      await t.tap(find.text('Cancel'));
      await pumpCatalog(t);
      expect(f.result, isFalse);
    }),
  );
  for (final kind in ['url', 'json']) {
    testWidgets(
      '$kind Cancel Import key maps and name field D-pad exits',
      (t) => catalogCase(t, (f) async {
        f.tv(true);
        await f.mount(t);
        await f.dialog(
          t,
          kind == 'url'
              ? StremioTvLocalCatalogsDialog.importFromUrl
              : StremioTvLocalCatalogsDialog.importFromJson,
        );
        final prefix = 'stremio-import-$kind-';
        final content = kind == 'url' ? 'url' : 'content';
        await focusCatalog(t, '${prefix}cancel');
        await keyCatalog(t, LogicalKeyboardKey.arrowRight);
        expect(catalogFocus('${prefix}import').hasPrimaryFocus, isTrue);
        await keyCatalog(t, LogicalKeyboardKey.arrowLeft);
        expect(catalogFocus('${prefix}cancel').hasPrimaryFocus, isTrue);
        await keyCatalog(t, LogicalKeyboardKey.arrowUp);
        expect(catalogFocus(prefix + content).hasFocus, isTrue);
        await focusCatalog(t, '${prefix}name');
        await keyCatalog(t, LogicalKeyboardKey.arrowUp);
        expect(catalogFocus('${prefix}cancel').hasPrimaryFocus, isTrue);
        await focusCatalog(t, '${prefix}name');
        await keyCatalog(t, LogicalKeyboardKey.arrowDown);
        expect(catalogFocus(prefix + content).hasFocus, isTrue);
        await focusCatalog(t, '${prefix}import');
        await keyCatalog(t, LogicalKeyboardKey.space);
        expect(
          find.text(kind == 'url' ? 'Enter a URL' : 'Paste JSON content'),
          findsOneWidget,
        );
        await focusCatalog(t, '${prefix}cancel');
        await keyCatalog(t, LogicalKeyboardKey.space);
        expect(f.result, isFalse);
      }),
    );
  }
  testWidgets(
    'JSON Up-at-start reaches Name, Down-at-end reaches Import, Esc Cancel',
    (t) => catalogCase(t, (f) async {
      await f.mount(t);
      await f.dialog(t, StremioTvLocalCatalogsDialog.importFromJson);
      await input(t, 1, '{}');
      field(t, 1).controller!.selection = const TextSelection.collapsed(
        offset: 0,
      );
      await focusCatalog(t, 'stremio-import-json-content');
      await keyCatalog(t, LogicalKeyboardKey.arrowUp);
      expect(catalogFocus('stremio-import-json-name').hasPrimaryFocus, isTrue);
      field(t, 1).controller!.selection = const TextSelection.collapsed(
        offset: 2,
      );
      await focusCatalog(t, 'stremio-import-json-content');
      await keyCatalog(t, LogicalKeyboardKey.arrowDown);
      expect(
        catalogFocus('stremio-import-json-import').hasPrimaryFocus,
        isTrue,
      );
      await focusCatalog(t, 'stremio-import-json-content');
      await keyCatalog(t, LogicalKeyboardKey.escape);
      expect(
        catalogFocus('stremio-import-json-cancel').hasPrimaryFocus,
        isTrue,
      );
      field(t, 1).controller!.clear();
      await focusCatalog(t, 'stremio-import-json-content');
      await keyCatalog(t, LogicalKeyboardKey.select);
      expect(
        catalogFocus('stremio-import-json-import').hasPrimaryFocus,
        isTrue,
      );
    }),
  );

  testWidgets(
    'review URL Cancel and Import left right and Cancel up key targets',
    (t) => catalogCase(t, (f) async {
      f.tv(true);
      await f.mount(t);
      await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await focusCatalog(t, 'stremio-import-url-cancel');
        await keyCatalog(t, key);
        expect(
          catalogFocus('stremio-import-url-import').hasPrimaryFocus,
          isTrue,
        );
        await focusCatalog(t, 'stremio-import-url-import');
        await keyCatalog(t, key);
        expect(
          catalogFocus('stremio-import-url-cancel').hasPrimaryFocus,
          isTrue,
        );
      }
      await keyCatalog(t, LogicalKeyboardKey.arrowUp);
      expect(catalogFocus('stremio-import-url-url').hasFocus, isTrue);
      expect(catalogFocus('stremio-import-url-name').hasFocus, isFalse);
    }),
  );
  for (final key in [LogicalKeyboardKey.select, LogicalKeyboardKey.space]) {
    testWidgets(
      'review URL Cancel ${key.keyLabel} pops without a result',
      (t) => catalogCase(t, (f) async {
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
        await focusCatalog(t, 'stremio-import-url-cancel');
        await keyCatalog(t, key);
        expect(f.result, isFalse);
        expect(f.observer.popped, hasLength(1));
        expect(await f.observer.popped.single.popped, isNull);
      }),
    );
  }
  testWidgets(
    'review URL queued Import activation while loading issues one request',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        final held = Completer<http.Response>();
        net.handler = (request) => held.future;
        try {
          await f.mount(t);
          await f.dialog(t, StremioTvLocalCatalogsDialog.importFromUrl);
          await input(t, 1, 'https://catalog.test/queued');
          await focusCatalog(t, 'stremio-import-url-import');
          // Two queued key events before rebuilding the disabled button: the
          // application guard owns the second event, rather than disabled focus.
          await t.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
          await t.sendKeyEvent(LogicalKeyboardKey.select, platform: 'android');
          await pumpCatalog(t, rounds: 2);
          expect(
            net.requests,
            hasLength(1),
            reason: 'loading suppresses queued activation',
          );
        } finally {
          held.complete(response(catalog()));
          await pumpCatalog(t);
        }
      }),
    ),
  );
  for (final key in [LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.select]) {
    testWidgets(
      'review JSON ${key.keyLabel} at nonempty end reaches Import and Esc Cancel',
      (t) => catalogCase(t, (f) async {
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromJson);
        await input(t, 1, '{}');
        field(t, 1).controller!.selection = const TextSelection.collapsed(
          offset: 2,
        );
        await focusCatalog(t, 'stremio-import-json-content');
        await keyCatalog(t, key);
        expect(
          catalogFocus('stremio-import-json-import').hasPrimaryFocus,
          isTrue,
        );
        await focusCatalog(t, 'stremio-import-json-content');
        await keyCatalog(t, LogicalKeyboardKey.escape);
        expect(
          catalogFocus('stremio-import-json-cancel').hasPrimaryFocus,
          isTrue,
        );
      }),
    );
  }
}
