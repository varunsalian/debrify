import 'dart:async';
import 'package:debrify/features/stremio_tv/application/stremio_tv_catalog_editor_dependencies.dart';
import 'package:debrify/features/stremio_tv/data/stremio_tv_catalog_editor.dart';
import 'package:debrify/features/stremio_tv/presentation/stremio_tv_catalog_picker_dialog.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    'append',
    'create',
    'duplicate',
    'failure',
    'covered',
    'retired',
    'unmount',
  ]) {
    testWidgets('catalog picker preserves $scenario behavior', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final gate = Completer<void>();
      final events = <String>[];
      var current = true;
      Future<StremioTvCatalogPickerResult?>? pending;
      final editor = StremioTvCatalogEditor(
        isCurrent: () => current,
        read: () async => [
          {
            'id': 'mine',
            'name': 'Mine',
            'type': 'movie',
            'items': scenario == 'duplicate'
                ? [
                    const StremioMeta(
                      id: 'tt123',
                      name: 'Fixture',
                      type: 'movie',
                    ).toJson(),
                  ]
                : [],
          },
        ],
        add: (value, guard) async {
          events.add('create');
          return guard();
        },
        update: (value, guard) async {
          events.add('append');
          if (['covered', 'retired', 'unmount'].contains(scenario)) {
            await gate.future;
          }
          return guard() && scenario != 'failure';
        },
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stremioTvCatalogEditorFactoryProvider.overrideWithValue(
              () => editor,
            ),
          ],
          child: MaterialApp(
            navigatorKey: nav,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () {
                    pending = StremioTvCatalogPickerDialog.show(
                      context,
                      item: const StremioMeta(
                        id: 'tt123',
                        name: 'Fixture',
                        type: 'movie',
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      if (scenario == 'create') {
        // Initial TV focus belongs to New Channel; Select opens the name form.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Weekend');
        await tester.tap(find.text('Create'));
        await tester.pumpAndSettle();
        expect((await pending)!.createdNew, isTrue);
        expect(events, ['create']);
      } else {
        await tester.tap(find.text('Mine'));
        await tester.pumpAndSettle();
        if (scenario == 'covered') {
          unawaited(
            nav.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('New page')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        if (scenario == 'retired') current = false;
        if (scenario == 'unmount') await tester.pumpWidget(const SizedBox());
        if (['covered', 'retired', 'unmount'].contains(scenario)) {
          gate.complete();
          await tester.pumpAndSettle();
        }
        if (scenario == 'duplicate' || scenario == 'failure') {
          expect(
            find.text(
              scenario == 'duplicate'
                  ? '"Fixture" is already in "Mine"'
                  : 'Failed to update channel',
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(await pending, isNull);
        } else if (scenario == 'retired') {
          expect(find.byType(SnackBar), findsNothing);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(await pending, isNull);
        } else if (scenario != 'unmount') {
          expect((await pending)!.message, 'Added "Fixture" to "Mine"');
        }
        if (scenario == 'covered') {
          expect(find.text('New page'), findsOneWidget);
        }
        if (scenario == 'duplicate') expect(events, isEmpty);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('disposing during catalog load creates no late focus nodes', (
    tester,
  ) async {
    final ready = Completer<List<Map<String, dynamic>>>();
    final editor = StremioTvCatalogEditor(
      isCurrent: () => true,
      read: () => ready.future,
      add: (_, _) async => true,
      update: (_, _) async => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StremioTvCatalogPickerDialog(
          item: const StremioMeta(id: 'tt1', type: 'movie', name: 'Fixture'),
          editor: editor,
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    ready.complete([
      {'id': 'mine', 'name': 'Mine'},
    ]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
