import 'dart:async';

import 'package:debrify/features/home/application/home_catalog_dependencies.dart';
import 'package:debrify/features/home/data/home_catalog_repository.dart';
import 'package:debrify/features/home/models/home_catalog_plan.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/filtered_catalog_pager.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../home_progressive_pagination_test.dart' show HomeFixture;

class PausedCatalogs extends HomeCatalogRepository {
  PausedCatalogs()
    : super(
        readAddons: StremioService.instance.getCatalogAddons,
        fetchPage: (_, _, _, _) async =>
            throw StateError('unexpected raw fetch'),
        readHides: () => null,
      );
  final firstPage = Completer<FilteredPage>();
  final resumed = <String>[];
  static const exhausted = FilteredPage(
    items: [],
    nextSkip: 200,
    exhausted: true,
    fetches: 1,
  );

  @override
  Future<List<CatalogSection>> fetchBatch(
    List<HomeCatalogReference> references, {
    Map<String, CatalogSection> previousRows = const {},
    required bool Function() isCurrent,
    void Function(CatalogSection)? onSection,
  }) async {
    final rows = <CatalogSection>[];
    for (final (addon, catalog) in references) {
      final row = CatalogSection(
        title: catalog.name,
        addon: addon,
        catalog: catalog,
        items: [
          StremioMeta(
            id: 'fixture:${catalog.id}',
            type: 'movie',
            name: catalog.id == 'fast' ? 'Fast 0' : catalog.name,
          ),
        ],
        pagingPaused: true,
        nextSkip: 100,
      );
      rows.add(row);
      onSection?.call(row);
    }
    return rows;
  }

  @override
  Future<FilteredPage> fetchRowPage(
    HomeCatalogReference reference, {
    required int skip,
    required Iterable<String> existingIds,
    required bool Function() isCurrent,
  }) {
    resumed.add(reference.$2.id);
    return resumed.length == 1 ? firstPage.future : Future.value(exhausted);
  }
}

void main() {
  testWidgets(
    'real Home resumes four rows per press, retains busy focus and restores after exhaustion',
    (tester) async {
      final repository = PausedCatalogs();
      addTearDown(() {
        if (!repository.firstPage.isCompleted) {
          repository.firstPage.complete(PausedCatalogs.exhausted);
        }
      });
      final home = HomeFixture(tester);
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeCatalogRepositoryProvider.overrideWithValue(repository),
          ],
          child: child,
        ),
      );
      await home.settle();
      final button = find.text('Continue paused rows');
      expect(button, findsOneWidget);
      final node = Focus.of(tester.element(button));
      node.requestFocus();
      await home.pump(Duration.zero);
      await home.key(LogicalKeyboardKey.enter);
      await home.pump(Duration.zero);
      expect(repository.resumed, ['fast']);
      expect(find.text('Continue paused rows · Loading…'), findsOneWidget);
      expect(node.hasFocus, isTrue);
      await home.key(LogicalKeyboardKey.enter);
      expect(repository.resumed, ['fast']);
      await home.drive(
        () => repository.firstPage.complete(PausedCatalogs.exhausted),
      );
      await home.settle();
      expect(repository.resumed, ['fast', 'slow0', 'slow1', 'slow2']);
      expect(node.hasFocus, isTrue);
      expect(button, findsOneWidget);
      await home.key(LogicalKeyboardKey.enter);
      await home.settle();
      expect(repository.resumed, [
        'fast',
        'slow0',
        'slow1',
        'slow2',
        'slow3',
        'slow4',
        'slow5',
        'slow6',
      ]);
      expect(button, findsNothing);
      expect(FocusManager.instance.primaryFocus, isNotNull);
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      expect(tester.takeException(), isNull);
    },
  );
}
