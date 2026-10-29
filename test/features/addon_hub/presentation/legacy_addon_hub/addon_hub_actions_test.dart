import 'dart:io';
import 'dart:convert';

import 'package:debrify/models/stremio_addon.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../../../support/addon_hub_fixture.dart';

void main() {
  testWidgets(
    'sheet tiles order and Disable Enable preserve stored position without confirmation',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        await f.tap(t, 'Zulu');
        expect(
          t
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .where(
                (s) => [
                  'Disable',
                  'Update',
                  'Rename',
                  'View details',
                  'Remove',
                ].contains(s),
              ),
          ['Disable', 'Update', 'Rename', 'View details', 'Remove'],
        );
        await f.tap(t, 'Disable');
        await f.until(
          t,
          () =>
              f.member('installedLoading') == false &&
              !(f.member('installed') as List<StremioAddon>).first.enabled,
        );
        var saved = await f.saved(t);
        expect(saved.map((a) => a.id), ['z9', 'com.linvo.cinemeta', 'a2']);
        expect(saved.first.enabled, isFalse);
        expect(find.byType(Dialog), findsNothing);
        await f.options(t, 'Zulu', 'Enable');
        await f.until(
          t,
          () => (f.member('installed') as List<StremioAddon>).first.enabled,
        );
        saved = await f.saved(t);
        expect(saved.first.enabled, isTrue);
        expect(f.requests, isEmpty);
      });
    },
  );
  for (final choice in ['Cancel', 'Save', 'Use manifest name']) {
    testWidgets(
      'rename $choice writes alias by storage key and retains order',
      (t) async {
        await hubCase(t, (f) async {
          await f.mount(t);
          await f.options(t, 'Zulu', 'Rename');
          expect(find.byType(TextFormField), findsOneWidget);
          await t.enterText(find.byType(TextFormField), '  New alias  ');
          await f.tap(t, choice);
          if (choice != 'Cancel') {
            await f.until(
              t,
              () =>
                  f.member('installedLoading') == false &&
                  find
                      .text(
                        choice == 'Save'
                            ? 'Renamed to New alias'
                            : 'Using Zulu',
                      )
                      .evaluate()
                      .isNotEmpty,
            );
          }
          final saved = await f.saved(t);
          expect(saved.map((a) => a.id), ['z9', 'com.linvo.cinemeta', 'a2']);
          expect(
            saved.first.userAlias,
            choice == 'Save' ? 'New alias' : isNull,
          );
          expect(f.requests, isEmpty);
        });
      },
    );
  }
  for (final confirm in [false, true]) {
    testWidgets('remove confirmation $confirm rereads persisted collection', (
      t,
    ) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        await f.options(t, 'Zulu', 'Remove');
        await f.until(t, () => find.text('Remove addon').evaluate().isNotEmpty);
        expect(find.text('Remove "Zulu" from your addons?'), findsOneWidget);
        await f.tap(t, confirm ? 'Remove' : 'Cancel');
        if (confirm) {
          await f.until(
            t,
            () =>
                f.ids('installed').length == 2 &&
                f.member('installedLoading') == false,
          );
        }
        expect(
          (await f.saved(t)).map((a) => a.id),
          confirm
              ? ['com.linvo.cinemeta', 'a2']
              : ['z9', 'com.linvo.cinemeta', 'a2'],
        );
        expect(f.requests, isEmpty);
      });
    });
  }
  testWidgets('details Copy URL copies exact manifest then closes dialog', (
    t,
  ) async {
    await hubCase(t, (f) async {
      await f.mount(t);
      await f.options(t, 'Zulu', 'View details');
      expect(find.text('ID'), findsOneWidget);
      expect(find.text('VERSION'), findsOneWidget);
      await f.tap(t, 'Copy URL');
      await t.pumpAndSettle();
      expect(f.clipboard, ['https://z9.addon.test/manifest.json']);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('URL copied to clipboard'), findsOneWidget);
      expect(f.requests, isEmpty);
    });
  });
  for (final outcome in ['same', 'new', 'failed']) {
    testWidgets('Update $outcome requests manifest URL with no confirmation', (
      t,
    ) async {
      await hubCase(t, (f) async {
        f.responses['https://z9.addon.test/manifest.json'] = outcome == 'failed'
            ? http.Response('fixture failure', 500)
            : f.json(
                hubManifest(
                  'z9',
                  'Zulu',
                  version: outcome == 'new' ? '2.0.0' : '1.0.0',
                ),
              );
        await f.mount(t);
        await f.options(t, 'Zulu', 'Update');
        final expected = outcome == 'new'
            ? 'Zulu updated (v1.0.0 → v2.0.0)'
            : outcome == 'same'
            ? 'Zulu is already up to date'
            : 'Failed to update Zulu';
        await f.until(t, () => find.text(expected).evaluate().isNotEmpty);
        expect(f.requests, ['GET https://z9.addon.test/manifest.json']);
        expect(find.byType(Dialog), findsNothing);
        expect(
          (await f.saved(t)).first.version,
          outcome == 'new' ? '2.0.0' : '1.0.0',
        );
        final snack = t.widget<SnackBar>(find.byType(SnackBar));
        expect(
          snack.backgroundColor,
          outcome == 'failed' ? Colors.red : isNull,
        );
      });
    });
  }
  for (final cancel in [false, true]) {
    testWidgets('Add addon input $cancel exact fetch and appended order', (
      t,
    ) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        await f.tap(t, 'Add addon');
        await t.enterText(
          find.byType(TextField),
          ' https://b3.addon.test/manifest.json ',
        );
        await f.tap(t, cancel ? 'Cancel' : 'Add');
        if (!cancel) {
          await f.until(
            t,
            () =>
                f.ids('installed').length == 4 &&
                f.member('installedLoading') == false,
          );
        }
        expect(
          (await f.saved(t)).map((a) => a.id),
          cancel
              ? ['z9', 'com.linvo.cinemeta', 'a2']
              : ['z9', 'com.linvo.cinemeta', 'a2', 'b3'],
        );
        expect(
          f.requests,
          cancel ? [] : ['GET https://b3.addon.test/manifest.json'],
        );
      });
    });
  }
  testWidgets(
    'Add addon manifest failure strips outer Exception prefix and shows red snackbar',
    (t) async {
      await hubCase(t, (f) async {
        f.responses['https://b3.addon.test/manifest.json'] = http.Response(
          'failure',
          500,
        );
        await f.mount(t);
        await f.tap(t, 'Add addon');
        await t.enterText(
          find.byType(TextField),
          'https://b3.addon.test/manifest.json',
        );
        await f.tap(t, 'Add');
        await f.until(t, () => find.byType(SnackBar).evaluate().isNotEmpty);
        final snack = t.widget<SnackBar>(find.byType(SnackBar));
        expect(
          (snack.content as Text).data,
          startsWith('Failed to fetch manifest: Exception: HTTP 500'),
        );
        expect(snack.backgroundColor, Colors.red);
        expect((await f.saved(t)).length, 3);
        expect(f.requests, ['GET https://b3.addon.test/manifest.json']);
      });
    },
  );
  testWidgets('overflow menu item order and Update all has no confirmation', (
    t,
  ) async {
    await hubCase(t, (f) async {
      await f.mount(t);
      await t.tap(find.byIcon(Icons.more_horiz_rounded));
      await t.pumpAndSettle();
      expect(
        t
            .widgetList<PopupMenuItem<String>>(
              find.byType(PopupMenuItem<String>),
            )
            .map((w) => w.value),
        ['import', 'update', 'auto', 'delete'],
      );
      await f.tap(t, 'Update all');
      await f.until(t, () => find.byType(SnackBar).evaluate().isNotEmpty);
      expect(f.requests, [
        'GET https://z9.addon.test/manifest.json',
        'GET https://com.linvo.cinemeta.addon.test/manifest.json',
        'GET https://a2.addon.test/manifest.json',
      ]);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('3 up to date'), findsOneWidget);
      expect((await f.saved(t)).map((a) => a.id), [
        'z9',
        'com.linvo.cinemeta',
        'a2',
      ]);
    });
  });
  for (final cancel in [true, false]) {
    testWidgets('Delete all $cancel confirms and persists exactly', (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        await t.tap(find.byIcon(Icons.more_horiz_rounded));
        await t.pumpAndSettle();
        await f.tap(t, 'Delete all');
        await f.until(
          t,
          () => find.text('Delete all addons?').evaluate().isNotEmpty,
        );
        await f.tap(t, cancel ? 'Cancel' : 'Delete all');
        if (!cancel) {
          await f.until(
            t,
            () =>
                f.ids('installed').isEmpty &&
                f.member('installedLoading') == false,
          );
        }
        expect((await f.saved(t)).length, cancel ? 3 : 0);
        expect(f.requests, isEmpty);
      });
    });
  }
  for (final variant in ['cancel', 'extension', 'bytes', 'path']) {
    testWidgets(
      'JSON import $variant picker args file-order append and result rows',
      (t) async {
        await hubCase(t, (f) async {
          final json = jsonEncode([
            {'transportUrl': 'https://b3.addon.test/manifest.json'},
            {'transportUrl': 'https://m7.addon.test/manifest.json'},
          ]);
          if (variant != 'cancel') {
            final file = File('${f.directory.path}/input.json');
            await t.runAsync(() => file.writeAsString(json));
            f.picker.supply(
              variant == 'extension' ? 'input.txt' : 'input.json',
              json,
              path: file.path,
              bytes: variant != 'path',
            );
          }
          await f.mount(t);
          await t.tap(find.byIcon(Icons.more_horiz_rounded));
          await t.pumpAndSettle();
          await f.tap(t, 'Import from JSON');
          await f.until(t, () => f.picker.calls.isNotEmpty);
          expect(f.picker.calls.single, {
            'type': FileType.any,
            'allowMultiple': false,
            'withData': true,
            'allowedExtensions': null,
          });
          if (variant == 'bytes' || variant == 'path') {
            await f.until(
              t,
              () => find.text('Import complete').evaluate().isNotEmpty,
            );
            final texts = t
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data)
                .where(
                  (x) => [
                    'Found',
                    'Imported',
                    'Already installed',
                    'Unsupported',
                    'Failed',
                  ].contains(x),
                );
            expect(texts, ['Found', 'Imported', 'Already installed']);
            await f.tap(t, 'Done');
            expect((await f.saved(t)).map((a) => a.id), [
              'z9',
              'com.linvo.cinemeta',
              'a2',
              'b3',
              'm7',
            ]);
            expect(f.requests, [
              'GET https://b3.addon.test/manifest.json',
              'GET https://m7.addon.test/manifest.json',
            ]);
          } else {
            if (variant == 'extension') {
              await f.until(
                t,
                () => find
                    .text('Please select the Stremio addon JSON export.')
                    .evaluate()
                    .isNotEmpty,
              );
            }
            expect((await f.saved(t)).length, 3);
            expect(f.requests, isEmpty);
          }
        });
      },
    );
  }
  for (final mode in ['true', 'false', 'throw']) {
    testWidgets(
      'Configure browser $mode clipboard fallback exact mode and duration',
      (t) async {
        await hubCase(t, (f) async {
          f.urls.result = mode == 'true';
          f.urls.fail = mode == 'throw';
          await f.mount(t);
          await f.dropdown(t, 'Installed', 'Official');
          await f.tap(t, 'Configure');
          await f.until(
            t,
            () =>
                f.urls.calls.isNotEmpty &&
                (mode == 'true' || f.clipboard.isNotEmpty),
          );
          expect(f.urls.calls.single.$1, 'https://m7.addon.test/configure');
          expect(
            f.urls.calls.single.$2.mode,
            PreferredLaunchMode.externalApplication,
          );
          expect(
            f.clipboard,
            mode == 'true' ? [] : ['https://m7.addon.test/configure'],
          );
          if (mode != 'true') {
            expect(
              t.widget<SnackBar>(find.byType(SnackBar)).duration,
              const Duration(seconds: 5),
            );
          }
          expect(f.requests, isEmpty);
          expect((await f.saved(t)).length, 3);
        });
      },
    );
  }
  testWidgets(
    'market install appends reloads twice and refocuses retained pool node',
    (t) async {
      await hubCase(t, (f) async {
        await f.mount(t);
        await f.dropdown(t, 'Installed', 'Official');
        final nodes = f.member('marketNodes') as List<FocusNode>;
        final revision = f.member('installedLoadRevision') as int;
        nodes.first.requestFocus();
        await t.pump();
        await f.tapInRow(t, 'Middle', 'Install');
        await f.until(
          t,
          () =>
              f.ids('installed').contains('m7') &&
              f.member('installedLoading') == false,
        );
        await t.pump();
        await t.pump();
        await t.pumpAndSettle();
        expect(f.member('installedLoadRevision'), revision + 2);
        expect(f.requests, ['GET https://m7.addon.test/manifest.json']);
        expect((await f.saved(t)).map((a) => a.id), [
          'z9',
          'com.linvo.cinemeta',
          'a2',
          'm7',
        ]);
        expect(
          (f.member('marketNodes') as List<FocusNode>).first,
          same(nodes.first),
        );
        expect(nodes.first.hasFocus, isTrue);
        expect(nodes.last.context!.mounted, isTrue);
        expect(nodes.last.hasFocus, isFalse);
      });
    },
  );
}
