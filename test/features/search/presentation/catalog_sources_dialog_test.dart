import 'dart:async';

import 'package:debrify/features/search/application/search_providers.dart';
import 'package:debrify/features/search/application/catalog_sources_controller.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/features/search/presentation/catalog_sources_dialog.dart';
import 'package:debrify/features/search/presentation/source_toggle_row.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_catalog_search_repository.dart';

void main() {
  late FakeCatalogSearchRepository repository;
  late SearchSession session;
  late ProviderContainer container;
  late BuildContext host;

  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    repository = FakeCatalogSearchRepository()
      ..addons = [
        for (final id in ['First', 'Second'])
          StremioAddon(
            id: id,
            name: id,
            baseUrl: 'https://$id.invalid',
            manifestUrl: 'https://$id.invalid/manifest.json',
            catalogs: const [
              StremioAddonCatalog(
                id: 'movies',
                type: 'movie',
                name: 'Movies',
                extraSupported: ['search'],
              ),
            ],
          ),
      ]
      ..disabled = {'Second'};
    session = SearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
  });

  tearDown(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          catalogSearchRepositoryProvider.overrideWith(
            (ref, key) => repository,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              host = context;
              return TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => CatalogSourcesDialog(session: session),
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    container = ProviderScope.containerOf(host);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Select and pointer toggle immediately; Done releases dialog state',
    (tester) async {
      await mount(tester);
      expect(
        tester
            .widgetList<SourceToggleRow>(find.byType(SourceToggleRow))
            .map((w) => w.enabled),
        [true, false],
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(repository.writes, [
        {'Second', 'First'},
      ]);
      await tester.tap(find.text('Second'));
      await tester.pumpAndSettle();
      expect(repository.writes.last, {'First'});
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogSourcesDialog), findsNothing);
      expect(container.exists(catalogSourcesProvider(session)), isFalse);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<SourceToggleRow>(find.byType(SourceToggleRow))
            .map((w) => w.enabled),
        [false, true],
      );
      expect(repository.writes, hasLength(2));
    },
  );

  testWidgets('bulk actions save value snapshots before dismissal', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('Disable all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable all'));
    await tester.pumpAndSettle();
    expect(repository.writes, [
      {'First', 'Second'},
      <String>{},
    ]);
    expect(find.byType(CatalogSourcesDialog), findsOneWidget);
  });

  testWidgets('an expired profile cannot dispatch a dialog mutation', (
    tester,
  ) async {
    await mount(tester);
    repository.isCurrent = false;
    await tester.tap(find.text('Disable all'));
    await tester.pumpAndSettle();
    expect(repository.writes, isEmpty);
    expect(
      tester
          .widgetList<SourceToggleRow>(find.byType(SourceToggleRow))
          .map((w) => w.enabled),
      [true, false],
    );
  });

  testWidgets('a pending immediate save survives Done without replay', (
    tester,
  ) async {
    final saved = Completer<void>();
    repository.write = (_) => saved.future;
    await mount(tester);
    await tester.tap(find.text('Disable all'));
    await tester.pump();
    expect(repository.writes, [
      {'First', 'Second'},
    ]);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(container.exists(catalogSourcesProvider(session)), isFalse);
    saved.complete();
    await tester.pump();
    expect(repository.writes, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('no addons keeps explanatory text and removes bulk actions', (
    tester,
  ) async {
    repository.addons = [];
    await mount(tester);
    expect(
      find.textContaining('No search-capable addons installed.'),
      findsOneWidget,
    );
    expect(find.text('Enable all'), findsNothing);
    expect(find.text('Disable all'), findsNothing);
    expect(repository.writes, isEmpty);
  });
  testWidgets(
    'profile replacement removes outgoing dialog data without new IO',
    (tester) async {
      await mount(tester);
      expect(find.text('First'), findsOneWidget);
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'next', dataGeneration: 1, sessionEpoch: 2),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsNothing);
      expect(repository.writes, isEmpty);
      expect(repository.requests, isEmpty);
    },
  );
}
