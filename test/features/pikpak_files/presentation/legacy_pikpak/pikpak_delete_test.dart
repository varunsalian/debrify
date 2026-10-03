import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/pikpak_files_fixture.dart';

void main() {
  for (final action in ['Cancel', 'Move to Trash', 'Delete Permanently']) {
    testWidgets(
      'single delete real row menu $action exact POST and snackbar ordering',
      (t) => pikpakCase(t, (f) async {
        await f.mount(t);
        await t.tap(find.byTooltip('More options').first);
        await t.pumpAndSettle();
        await t.tap(find.text('Delete'));
        await t.pumpAndSettle();
        expect(find.text('Delete File'), findsOneWidget);
        expect(
          t
              .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
              .autofocus,
          isTrue,
        );
        if (action != 'Cancel') f.heldPost = Completer<http.Response>();
        await t.tap(find.text(action));
        await t.pump();
        if (action == 'Cancel') {
          expect(f.requests.length, 1);
          expect(f.ids, ['z9', 'a2', 'm5']);
          return;
        }
        await f.until(t, () => f.requests.length == 2);
        expect(
          find.text(
            action == 'Move to Trash'
                ? 'Moving to trash...'
                : 'Deleting permanently...',
          ),
          findsOneWidget,
        );
        expect(f.ids, ['z9', 'a2', 'm5']);
        await t.pump(const Duration(milliseconds: 600));
        expect(find.text('Delete File'), findsNothing);
        expect(f.requests.map((r) => (r.method, r.url.path)), [
          ('GET', '/drive/v1/files'),
          (
            'POST',
            '/drive/v1/files:${action == 'Move to Trash' ? 'batchTrash' : 'batchDelete'}',
          ),
        ]);
        expect(jsonDecode(f.requests.last.body), {
          'ids': ['z9'],
        });
        f.heldPost!.complete(f.json({}));
        await f.until(t, () => f.ids.length == 2);
        expect(f.ids, ['a2', 'm5']);
        await t.pump();
        expect(f.member('selectedFileIds'), isEmpty);
      }),
    );
  }
  for (final action in ['Cancel', 'Move to Trash', 'Delete Permanently']) {
    for (final failure in [false, true]) {
      testWidgets(
        'batch delete real selection dialog $action failure=$failure insertion order snapshot after close',
        (t) => pikpakCase(t, (f) async {
          await f.mount(t);
          await t.tap(find.byTooltip('Select items'));
          await t.pump();
          await t.tap(find.text('Video m5.mkv'));
          await t.tap(find.text('Folder z9'));
          await t.pump();
          expect(f.member('selectedFileIds'), ['m5', 'z9']);
          await t.tap(find.widgetWithText(FilledButton, 'Delete'));
          await t.pumpAndSettle();
          expect(find.text('Delete 2 files'), findsOneWidget);
          expect(
            t
                .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
                .autofocus,
            isTrue,
          );
          // Dialog does not snapshot yet: preserve the observed after-close behavior.
          f.member('toggleFileSelection')('a2');
          await t.pump();
          f.failPost = failure;
          if (action != 'Cancel') f.heldPost = Completer<http.Response>();
          await t.tap(find.text(action));
          await t.pump();
          if (action == 'Cancel') {
            expect(f.requests.length, 1);
            expect(f.ids, ['z9', 'a2', 'm5']);
            expect(f.member('selectedFileIds'), ['m5', 'z9', 'a2']);
            expect(f.member('isSelectionMode'), isTrue);
            return;
          }
          await f.until(t, () => f.requests.length == 2);
          expect(jsonDecode(f.requests.last.body), {
            'ids': ['m5', 'z9', 'a2'],
          });
          expect(f.ids, ['z9', 'a2', 'm5']);
          expect(f.member('isSelectionMode'), isTrue);
          await t.pump(const Duration(milliseconds: 600));
          expect(find.text('Delete 2 files'), findsNothing);
          f.heldPost!.complete(
            failure
                ? f.json({'error_description': 'fixture post failure'}, 500)
                : f.json({}),
          );
          await f.until(t, () => f.member('isSelectionMode') == false);
          await t.pump();
          expect(f.ids, failure ? ['z9', 'a2', 'm5'] : <String>[]);
          expect(f.member('selectedFileIds'), isEmpty);
          expect(f.requests.map((r) => (r.method, r.url.path)), [
            ('GET', '/drive/v1/files'),
            (
              'POST',
              '/drive/v1/files:${action == 'Move to Trash' ? 'batchTrash' : 'batchDelete'}',
            ),
          ]);
        }),
      );
    }
  }
  for (final metadataError in [false, true]) {
    testWidgets(
      'restricted startup metadata false logs out error=$metadataError',
      (t) => pikpakCase(
        t,
        (f) async {
          f.details['restricted'] = pikpakFile('restricted');
          if (metadataError) f.failingDetails.add('restricted');
          await f.mount(t, wait: false);
          await f.until(t, () => f.member('initialLoad') == false);
          await t.pump();
          expect(f.member('pikpakEnabled'), isFalse);
          expect(f.member('restrictedFolderId'), isNull);
          expect(await t.runAsync(PikpakStorage.getPikPakAccessToken), isNull);
          expect(await t.runAsync(PikpakStorage.getPikPakEmail), isNull);
          expect(
            await t.runAsync(PikpakStorage.getPikPakRestrictedFolderId),
            isNull,
          );
          expect(f.requests.map((r) => (r.method, r.url.path)), [
            ('GET', '/drive/v1/files/restricted'),
          ]);
          expect(
            find.text(
              'Restricted folder was deleted. You have been logged out.',
            ),
            findsOneWidget,
          );
        },
        preferences: {
          'pikpak_restricted_folder_id': 'restricted',
          'pikpak_restricted_folder_name': 'Restricted',
        },
      ),
    );
  }
  testWidgets(
    'restricted root any load error logs out and clears credentials',
    (t) => pikpakCase(
      t,
      (f) async {
        f.failLists = true;
        await f.mount(t, wait: false);
        await f.until(t, () => f.member('initialLoad') == false);
        await t.pump();
        expect(f.member('pikpakEnabled'), isFalse);
        expect(f.member('currentFolderId'), 'restricted');
        expect(f.member('isLoading'), isFalse);
        expect(await t.runAsync(PikpakStorage.getPikPakRefreshToken), isNull);
        expect(f.requests.map((r) => (r.method, r.url.path)), [
          ('GET', '/drive/v1/files/restricted'),
          ('GET', '/drive/v1/files'),
        ]);
        expect(
          find.text('Restricted folder was deleted. You have been logged out.'),
          findsOneWidget,
        );
      },
      preferences: {
        'pikpak_restricted_folder_id': 'restricted',
        'pikpak_restricted_folder_name': 'Restricted',
      },
    ),
  );
  testWidgets(
    'restriction read outer service catch remains true without HTTP',
    (t) => pikpakCase(t, (f) async {
      ProfileRuntime.debugReset();
      expect(
        await t.runAsync(
          PikPakApiService.instance.verifyRestrictedFolderExists,
        ),
        isTrue,
      );
      expect(f.requests, isEmpty);
      ProfileRuntime.initializeLegacy();
    }),
  );
}
