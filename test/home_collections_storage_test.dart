import 'dart:convert';
import 'package:debrify/services/storage_service.dart';
import 'dart:io';
import 'dart:typed_data';
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
    'retired folder-list flags are migrated while Home row flags survive',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'home_disabled_sections_v1',
        jsonEncode([
          'collectionlist:c:f:old',
          'collection:c',
          'cw:movies',
          'future:row',
        ]),
      );
      expect(await StorageService.getHomeDisabledSections(), {
        'collection:c',
        'cw:movies',
        'future:row',
      });
      expect(
        jsonDecode(prefs.getString('home_disabled_sections_v1')!),
        unorderedEquals(['collection:c', 'cw:movies', 'future:row']),
      );
      await StorageService.setHomeDisabledSections({
        'collectionlist:c:f:old',
        'cw:series',
      });
      expect(await StorageService.getHomeDisabledSections(), {'cw:series'});
      await prefs.setString(
        'home_disabled_sections_v1',
        jsonEncode(['collectionlist:c:f:old']),
      );
      expect(await StorageService.getHomeDisabledSections(), isEmpty);
      expect(prefs.containsKey('home_disabled_sections_v1'), isFalse);
    },
  );

  test('stored and freshly imported native rows share one identity', () {
    final inventory = HomeCollectionInventory.decode(
      jsonEncode([
        {
          'id': 'c',
          'title': 'C',
          'folders': [
            {
              'id': 'f',
              'title': 'F',
              'sources': [
                {
                  'provider': 'tmdb',
                  'tmdbSourceType': 'LIST',
                  'tmdbId': 42,
                  'title': 'Original',
                },
              ],
            },
          ],
        },
      ]),
    );
    expect(inventory.collections.single.serializationVersion, 2);
    final source = inventory.collections.single.folders.single.sources.single;
    final fresh = CollectionCatalogSource.fromJson({
      'provider': 'tmdb',
      'tmdbSourceType': 'LIST',
      'tmdbId': 42,
      'title': 'New title',
    })!;
    expect(source.catalogId, fresh.catalogId);
    final renamed = CollectionCatalogSource.fromJson({
      ...source.toJson(),
      'title': 'Renamed',
    })!;
    expect(
      HomeCollectionRowIds.folderList('c', 'f', renamed),
      HomeCollectionRowIds.folderList('c', 'f', fresh),
    );
  });

  test('legacy stored GIFs migrate, but new explicit false survives', () async {
    final legacy = {
      'id': 'old',
      'title': 'Old',
      'folders': [
        {
          'id': 'f',
          'title': 'F',
          'focusGifUrl': 'https://example.test/f.gif',
          'focusGifEnabled': false,
        },
      ],
    };
    final oldText = jsonEncode([legacy]);
    SharedPreferences.setMockInitialValues({
      HomeCollectionInventory.legacyPrefsKey: oldText,
    });
    final store = HomeCollectionsStore();
    expect(
      (await store.getCollections()).single.folders.single.focusGifEnabled,
      true,
    );
    await store.setEnabled('old', false);
    expect(
      (await store.getCollections()).single.folders.single.focusGifEnabled,
      true,
    );
    // Downgrades retain the original readable snapshot, separate from new data.
    expect(
      (await SharedPreferences.getInstance()).getString(
        HomeCollectionInventory.legacyPrefsKey,
      ),
      oldText,
    );
    await store.importJson(
      jsonEncode([
        {...legacy, 'id': 'new'},
      ]),
    );
    expect(
      (await store.getCollections()).last.folders.single.focusGifEnabled,
      false,
    );
  });

  test('real native pack fits tvOS preferences and survives backup', () async {
    ProfilePreferenceBudget.debugEnforcedOverride = true;
    final json = utf8.decode(
      gzip.decode(
        File(
          'test/fixtures/collections/kaptain-native-0.61.json.gz',
        ).readAsBytesSync(),
      ),
    );
    final store = HomeCollectionsStore();
    await store.importJson(json);
    final raw = (await SharedPreferences.getInstance()).getString(
      HomeCollectionsStore.prefsKey,
    )!;
    expect(utf8.encode(raw).length, lessThan(128 * 1024));
    expect(jsonDecode(raw)['version'], 3);
    final collections = await store.getCollections();
    expect(collections.fold<int>(0, (n, c) => n + c.sourceCount), 1755);
    final backup = await store.exportJson();
    await store.clear();
    await store.applyBackup(backup);
    expect(
      (await store.getCollections()).fold<int>(0, (n, c) => n + c.sourceCount),
      1755,
    );
  });
  test('compressed inventory rejects invalid gzip and excessive expansion', () {
    String wrap(List<int> bytes) => jsonEncode({
      'version': 3,
      'encoding': 'gzip-base64',
      'data': base64Encode(bytes),
    });
    expect(
      () => HomeCollectionInventory.decode(wrap([1, 2, 3])),
      throwsA(anything),
    );
    final oversized = gzip.encode(
      Uint8List(HomeCollectionInventory.maxEnvelopeBytes + 1),
    );
    expect(
      () => HomeCollectionInventory.decode(wrap(oversized)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('32 MiB'),
        ),
      ),
    );
    final corrupt = gzip.encode(
      utf8.encode(jsonEncode(HomeCollectionInventory().toJson())),
    );
    corrupt[corrupt.length - 8] ^= 0xff;
    expect(
      () => HomeCollectionInventory.decode(wrap(corrupt)),
      throwsA(anything),
    );
  });

  test(
    'compressed corruption remains recoverable but never silently overwritten',
    () async {
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: jsonEncode({
          'version': 3,
          'encoding': 'gzip-base64',
          'data': 'broken',
        }),
      });
      final store = HomeCollectionsStore();
      expect((await store.getInventory()).hadCorruption, true);
      await expectLater(store.importCollections([c]), throwsFormatException);
    },
  );
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
      final large = HomeCollection(
        id: 'large',
        title: 'x' * (HomeCollectionInventory.maxStoredBytes + 1024),
      );
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
