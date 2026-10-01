import 'dart:async';

import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_catalog_workflow_test.dart'
    show addon, row, item, repository, mount;

void main() {
  late ProviderContainer container;
  late HomeCatalogController controller;
  late Completer<List<StremioMeta>> response;
  var current = true;
  var canContinue = true;
  var addonReads = 0;
  setUp(() {
    current = true;
    canContinue = true;
    addonReads = 0;
    response = Completer<List<StremioMeta>>();
    container = ProviderContainer.test(
      overrides: [
        homeCatalogRepositoryProvider.overrideWithValue(
          repository((_) => response.future),
        ),
      ],
    );
    controller = mount(
      container,
      HomeCatalogSession(
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      ),
    );
  });
  String rowId(CatalogSection section) =>
      '${section.addon.id}:${section.catalog.type}:${section.catalog.id}';
  CatalogSection section(String id) => CatalogSection(
    title: id,
    addon: addon,
    catalog: row(id).$2,
    items: [item(id)],
  );
  Future<
    ({
      List<CatalogSection> additions,
      List<CatalogSection> rows,
      bool appendOnly,
    })?
  >
  load() => controller.loadNextRows(
    1,
    generation: controller.generation,
    isCurrent: () => current,
    canContinue: () => canContinue,
    currentAddons: () {
      addonReads++;
      return {'fixture': addon};
    },
    rowId: rowId,
  );

  test(
    'tail page commits its cursor and preserves existing horizontal pages',
    () async {
      final first = section('first');
      controller.replaceRows([first]);
      controller.install([row('first'), row('tail')]);
      controller.reserve(1);
      final pending = load();
      // Horizontal paging can advance while the vertical request is pending.
      controller.appendRowItems(first, [item('horizontal')]);
      response.complete([item('tail')]);
      final page = (await pending)!;
      expect(page.appendOnly, isTrue);
      expect(page.rows.first, same(first));
      expect(first.items.map((i) => i.id), ['first', 'horizontal']);
      expect(page.additions.single.catalog.id, 'tail');
      expect(controller.current.committed!.cursor, 2);
      expect(addonReads, 1);
      expect(() => page.rows.clear(), throwsUnsupportedError);
      expect(() => page.additions.clear(), throwsUnsupportedError);
    },
  );

  test(
    'earlier recovered catalog requires reconciliation instead of appending',
    () async {
      final later = section('later');
      controller.replaceRows([later]);
      controller.install([row('earlier'), row('later')]);
      final pending = load();
      response.complete([item('earlier')]);
      final page = (await pending)!;
      expect(page.appendOnly, isFalse);
      expect(page.rows.map((r) => r.catalog.id), ['earlier', 'later']);
      expect(page.rows.last, same(later));
    },
  );

  test(
    'covered empty page commits cursor without replacing cached membership',
    () async {
      final visible = section('visible');
      controller.replaceRows([visible]);
      final previous = controller.rows;
      controller.install([row('empty'), row('tail')]);
      canContinue = false;
      final pending = load();
      response.complete([]);
      expect(await pending, isNull);
      expect(controller.rows, same(previous));
      expect(controller.current.committed!.cursor, 1);
      expect(controller.current.hasMore, isTrue);
    },
  );

  for (final retirement in ['profile', 'generation', 'dispose']) {
    test('$retirement retirement cannot commit or merge a late page', () async {
      final visible = section('visible');
      controller.replaceRows([visible]);
      controller.install([row('late')]);
      final pending = load();
      switch (retirement) {
        case 'profile':
          current = false;
        case 'generation':
          controller.beginLoad();
        case 'dispose':
          container.dispose();
      }
      response.complete([item('late')]);
      expect(await pending, isNull);
      expect(controller.rows, [visible]);
      expect(addonReads, 0);
      expect(controller.current.committed, isNull);
    });
  }
}
