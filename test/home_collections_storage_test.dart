import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_collection_inventory.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';

const c = HomeCollection(
  id: 'one',
  title: 'One',
  folders: [HomeCollectionFolder(id: 'f', title: 'Folder')],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    ProfilePreferenceBudget.debugReset();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(ProfilePreferenceBudget.debugReset);
  test(
    'visual fields survive storage, visibility, reimport and backup restore',
    () async {
      final store = HomeCollectionsStore();
      const original = HomeCollection(
        id: 'effects',
        title: 'Effects',
        focusGlowEnabled: false,
        folders: [
          HomeCollectionFolder(
            id: 'f',
            title: 'F',
            focusVideoUrl: 'https://example.test/focus.mp4',
            focusVideoEnabled: false,
          ),
        ],
      );
      await store.importJson(jsonEncode(original.toJson()));
      await store.setEnabled('effects', false);
      await store.importJson(jsonEncode(original.toJson()));
      final backup = await store.exportJson();
      SharedPreferences.setMockInitialValues({});
      await HomeCollectionsStore().applyBackup(backup);
      final restored = (await HomeCollectionsStore().getCollections()).single;
      expect(restored.enabled, isFalse);
      expect(restored.focusGlowEnabled, isFalse);
      expect(restored.folders.single.focusVideoEnabled, isFalse);
      expect(
        restored.folders.single.focusVideoUrl,
        'https://example.test/focus.mp4',
      );
      expect(
        HomeCollectionsStore.signatureOf([original]),
        isNot(
          HomeCollectionsStore.signatureOf([
            const HomeCollection(id: 'effects', title: 'Effects'),
          ]),
        ),
      );
    },
  );
  test('invalid sync order identities cannot enter storage', () async {
    final store = HomeCollectionsStore();
    for (final id in ['', 'bad\u0000id']) {
      await expectLater(
        store.importCollections([HomeCollection(id: id, title: 'Bad')]),
        throwsFormatException,
      );
    }
    expect(await store.getCollections(), isEmpty);
  });
  test('explicit save applies order and retains deletion records', () async {
    final store = HomeCollectionsStore();
    const two = HomeCollection(id: 'two', title: 'Two');
    const removed = HomeCollection(id: 'removed', title: 'Removed');
    await store.importCollections([c, two, removed]);
    await store.saveCollections([two, c]);
    expect((await store.getCollections()).map((item) => item.id), [
      'two',
      'one',
    ]);
    final prefs = await SharedPreferences.getInstance();
    final inventory = HomeCollectionInventory.decode(
      prefs.getString(HomeCollectionsStore.prefsKey),
    );
    expect(inventory.records.containsKey('removed'), true);
    expect(inventory.records['removed'], isNull);
  });
  test(
    'legacy preferences upgrade on mutation with explicit deletions',
    () async {
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: jsonEncode([c.toJson()]),
      });
      final store = HomeCollectionsStore();
      expect((await store.getCollections()).single.id, 'one');
      await store.clear();
      final raw = (await SharedPreferences.getInstance()).getString(
        HomeCollectionsStore.prefsKey,
      );
      expect(raw, isNotNull);
      final inventory = HomeCollectionInventory.decode(raw);
      expect(inventory.records.containsKey('one'), true);
      expect(inventory.records['one'], null);
      expect(await HomeCollectionsStore().getCollections(), isEmpty);
    },
  );
  test('reimport can deliberately restore a deleted collection', () async {
    final store = HomeCollectionsStore();
    await store.importCollections([c]);
    await store.remove('one');
    await store.importCollections([c]);
    expect((await store.getCollections()).single.title, 'One');
  });
  test(
    'reimport updates contents without resetting disabled state or order',
    () async {
      final store = HomeCollectionsStore();
      await store.importCollections([
        c,
        const HomeCollection(id: 'two', title: 'Two'),
      ]);
      await store.setEnabled('one', false);
      await store.importCollections([
        const HomeCollection(id: 'one', title: 'Updated'),
      ]);
      final list = await store.getCollections();
      expect(list.map((c) => c.id), ['one', 'two']);
      expect(list.first.title, 'Updated');
      expect(list.first.enabled, false);
    },
  );
  test(
    'backup array exports active records and restores their visibility',
    () async {
      final store = HomeCollectionsStore();
      await store.importCollections([
        c.copyWith(enabled: false),
        const HomeCollection(id: 'two', title: 'Two'),
      ]);
      await store.remove('two');
      final backup = await store.exportJson();
      expect(backup, hasLength(1));
      SharedPreferences.setMockInitialValues({});
      final report = await store.applyBackup(backup);
      expect(report.imported, 1);
      expect(report.failed, 0);
      expect((await store.getCollections()).single.enabled, false);
    },
  );
  test(
    'invalid persisted data is preserved until reset while reads and backup remain usable',
    () async {
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: 'broken',
      });
      final store = HomeCollectionsStore();
      await expectLater(store.importCollections([c]), throwsFormatException);
      expect(await store.exportJson(), isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString(
          HomeCollectionsStore.prefsKey,
        ),
        'broken',
      );
    },
  );
  test('reset and explicit restore recover a corrupt inventory', () async {
    SharedPreferences.setMockInitialValues({
      HomeCollectionsStore.prefsKey: 'broken',
    });
    final store = HomeCollectionsStore();
    expect((await store.getInventory()).hadCorruption, true);
    await store.clear();
    expect((await store.getInventory()).hadCorruption, false);
    await store.importCollections([c]);
    SharedPreferences.setMockInitialValues({
      HomeCollectionsStore.prefsKey: 'broken again',
    });
    await store.applyBackup([c.toJson()]);
    expect((await store.getCollections()).single.id, c.id);
  });
  test(
    'reads salvage valid records alongside a malformed collection',
    () async {
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: jsonEncode({
          'version': 2,
          'records': {'one': c.toJson(), 'bad': 123},
          'order': ['bad', 'one'],
        }),
      });
      final store = HomeCollectionsStore();
      expect((await store.getInventory()).hadCorruption, true);
      expect((await store.getEnabledCollections()).single.id, 'one');
      expect((await store.exportJson()).single['id'], 'one');
    },
  );
  test(
    'pending deletion identities do not consume live import capacity',
    () async {
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: jsonEncode({
          'version': 2,
          'records': {for (var i = 0; i < 1100; i++) 'deleted$i': null},
          'order': [for (var i = 0; i < 1100; i++) 'deleted$i'],
        }),
      });
      final store = HomeCollectionsStore();
      await store.importCollections([c]);
      expect((await store.getCollections()).single.id, 'one');
    },
  );
  test(
    'visibility changes remain possible on oversized synced definitions',
    () async {
      final large = HomeCollection(id: 'large', title: 'x' * (140 * 1024));
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: jsonEncode([large.toJson()]),
      });
      final store = HomeCollectionsStore();
      await store.setEnabled('large', false);
      expect((await store.getCollections()).single.enabled, false);
      await store.setEnabled('large', true);
      expect((await store.getCollections()).single.enabled, true);
    },
  );
  test(
    'oversized sync identities are refused without changing inventory',
    () async {
      final store = HomeCollectionsStore();
      await store.importCollections([c]);
      await expectLater(
        store.importCollections([
          HomeCollection(id: 'x' * 1024, title: 'Too long'),
        ]),
        throwsFormatException,
      );
      expect((await store.getCollections()).map((c) => c.id), ['one']);
    },
  );
  test('failed layout write surfaces a failure', () async {
    ProfilePreferenceBudget.debugEnforcedOverride = true;
    SharedPreferences.setMockInitialValues({'full': 'x' * (512 * 1024)});
    await expectLater(
      HomeCollectionsStore().setFolderLayout(CollectionFolderLayout.tabs),
      throwsStateError,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        HomeCollectionsStore.folderLayoutKey,
      ),
      null,
    );
  });
  test(
    'signature reflects content edits with identical counts and timestamps',
    () {
      expect(
        HomeCollectionsStore.signatureOf([c]),
        isNot(
          HomeCollectionsStore.signatureOf([
            const HomeCollection(
              id: 'one',
              title: 'Changed',
              folders: [HomeCollectionFolder(id: 'f', title: 'Folder')],
            ),
          ]),
        ),
      );
    },
  );
}
