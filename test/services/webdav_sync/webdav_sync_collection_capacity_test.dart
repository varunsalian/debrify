import 'dart:convert';
import 'dart:math';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_collection_inventory.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_collection_capacity.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = ProfileScope(
    profileId: 'tv',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final maps = WebDavSyncIdentityMaps(
    circleToLocalProfiles: {'circle': 'tv'},
    circleToLocalResources: {},
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(scope);
    ProfilePreferenceBudget.debugEnforcedOverride = true;
  });
  tearDown(() {
    ProfilePreferenceBudget.debugReset();
    ProfileRuntime.debugReset();
  });
  WebDavSyncBuiltHotState build(
    Map<String, Object?> prefs,
    int time, {
    WebDavSyncHotDocument? previous,
    String? deferred,
  }) => WebDavSyncHotMerge.build(
    WebDavSyncBuildInput(
      circleProfileId: 'circle',
      deviceId: 'device-tv',
      rawPreferences: prefs,
      portablePreferences: prefs,
      identityMaps: maps,
      localNowMs: time,
      clockOffsetMs: 0,
      serverNowMs: time,
      previous: previous,
      deferredCollectionLocal: deferred,
    ),
  );

  test(
    'stale capacity notice clears when no collection target remains',
    () async {
      final raw = await SharedPreferences.getInstance();
      await raw.setBool(
        '${scope.preferencePrefix}${HomeCollectionInventory.syncDeferredKey}',
        true,
      );
      final plan = WebDavSyncCollectionCapacity.plan(
        raw,
        scope.preferencePrefix,
        {'theme': 'dark'},
      );
      expect(plan.collectionsDeferred, false);
      expect(plan.values[HomeCollectionInventory.syncDeferredKey], false);
    },
  );

  test(
    'upgrade normalization preserves the original record and stamp, so a peer edit wins',
    () {
      final oldValue = {
        'id': 'old',
        'title': 'Before',
        'folders': [
          {
            'id': 'f',
            'title': 'Folder',
            'focusGifUrl': 'https://example.test/f.gif',
            'focusGifEnabled': false,
          },
        ],
      };
      final key = WebDavSyncRecordKey.homeCollection('old');
      const stamp = WebDavSyncStamp(
        normalizedTimeMs: 100,
        originDeviceId: 'device-old',
      );
      final records = {
        key: WebDavSyncStampedValue(stamp: stamp, value: oldValue),
      };
      final orders = {
        WebDavSyncRecordKey.homeCollectionOrder: WebDavSyncOrderValue(
          stamp: stamp,
          keys: ['old'],
        ),
      };
      final baseline = WebDavSyncHotDocument(
        circleProfileId: 'circle',
        scalars: build({}, 100).document.scalars,
        watchState: WebDavSyncWatchPart(
          stamp: stamp,
          semanticDigest: semanticDigestOf({
            'records': {
              for (final e in records.entries) e.key: e.value.toJson(),
            },
            'orders': {for (final e in orders.entries) e.key: e.value.toJson()},
          }),
          records: records,
          orders: orders,
        ),
      );
      final local = build(
        {
          HomeCollectionInventory.legacyPrefsKey: jsonEncode([oldValue]),
        },
        300,
        previous: baseline,
      ).document;
      expect(local.watchState.records[key]!.stamp.normalizedTimeMs, 100);
      expect(local.watchState.records[key]!.value, oldValue);
      final materialized = WebDavSyncHotMerge.materializePreferences(
        document: baseline,
        identityMaps: maps,
      );
      final roundTrip = build(materialized, 350, previous: baseline).document;
      expect(roundTrip.watchState.records[key]!.stamp.normalizedTimeMs, 100);
      expect(roundTrip.watchState.records[key]!.value, oldValue);
      final peer = build({
        HomeCollectionInventory.legacyPrefsKey: jsonEncode([
          {...oldValue, 'title': 'Peer edit'},
        ]),
      }, 200).document;
      for (final docs in [
        [local, peer],
        [peer, local],
      ]) {
        final merged = WebDavSyncHotMerge.merge(
          local: docs.first,
          peers: [docs.last],
          tombstoneDocuments: [],
          nowMs: 400,
        ).document;
        expect(
          (merged.watchState.records[key]!.value as Map)['title'],
          'Peer edit',
        );
      }
    },
  );

  test(
    'first interrupted deferred apply cannot invent an empty collection order',
    () {
      final pending = build({
        HomeCollectionInventory.prefsKey:
            (HomeCollectionInventory()
                  ..put(const HomeCollection(id: 'z', title: 'Z'))
                  ..put(const HomeCollection(id: 'a', title: 'A')))
                .encode(),
      }, 100).document;
      final fresh = build({}, 200, deferred: '[]').document;
      expect(
        fresh.watchState.orders.containsKey(
          WebDavSyncRecordKey.homeCollectionOrder,
        ),
        false,
      );
      final replay = WebDavSyncHotMerge.merge(
        local: fresh,
        peers: [pending],
        tombstoneDocuments: [],
        nowMs: 200,
      ).document;
      expect(
        replay.watchState.orders[WebDavSyncRecordKey.homeCollectionOrder]!.keys,
        ['z', 'a'],
      );
    },
  );

  test(
    'real enforced tvOS budget defers 7 MiB peer collection, keeps hot sync and later recovers',
    () async {
      final random = Random(17);
      final title = String.fromCharCodes(
        List.generate(7 * 1024 * 1024, (_) => 33 + random.nextInt(90)),
      );
      final inventory = HomeCollectionInventory()
        ..put(HomeCollection(id: 'remote', title: title));
      final encoded = inventory.encode();
      expect(
        utf8.encode(encoded).length,
        greaterThan(ProfilePreferenceBudget.emergencyLimitBytes),
      );
      final raw = await SharedPreferences.getInstance();
      final prefs = await ProfilePreferences.forCapturedScope(
        scope,
        CapturedProfilePreferenceAccess.syncApply,
      );
      final values = <String, Object>{
        HomeCollectionInventory.prefsKey: encoded,
        'playback_state_v1': '{"film":{"position":120}}',
        'finished_movies_v1': <String>['tt42'],
      };
      expect(
        await prefs.applySyncBatch(values, authorizationBarrier: () {}),
        false,
      );
      for (var tick = 0; tick < 3; tick++) {
        values['playback_state_v1'] = '{"film":{"position":${120 + tick}}}';
        final plan = WebDavSyncCollectionCapacity.plan(
          raw,
          scope.preferencePrefix,
          values,
        );
        expect(plan.collectionsDeferred, true);
        expect(
          await prefs.applySyncBatch(plan.values, authorizationBarrier: () {}),
          true,
        );
        expect(
          prefs.getString('playback_state_v1'),
          values['playback_state_v1'],
        );
        expect(prefs.getStringList('finished_movies_v1'), ['tt42']);
        expect(prefs.getBool(HomeCollectionInventory.syncDeferredKey), true);
        expect(prefs.getString(HomeCollectionInventory.prefsKey), isNull);
      }
      values[HomeCollectionInventory.prefsKey] = HomeCollectionInventory()
          .encode();
      final recovered = WebDavSyncCollectionCapacity.plan(
        raw,
        scope.preferencePrefix,
        values,
      );
      expect(recovered.collectionsDeferred, false);
      expect(
        await prefs.applySyncBatch(
          recovered.values,
          authorizationBarrier: () {},
        ),
        true,
      );
      expect(prefs.getBool(HomeCollectionInventory.syncDeferredKey), false);
    },
  );

  test(
    'deferred snapshot survives restart, preserves remote values, and permits genuine local edits',
    () {
      final local = HomeCollectionInventory()
        ..put(const HomeCollection(id: 'same', title: 'Local old'));
      final target = HomeCollectionInventory()
        ..put(const HomeCollection(id: 'same', title: 'Remote new'))
        ..put(const HomeCollection(id: 'unseen', title: 'Unseen'));
      final baseline = build({
        HomeCollectionInventory.prefsKey: target.encode(),
      }, 200).document;
      final persisted = WebDavSyncProfileEngineState.fromJson(
        jsonDecode(
          jsonEncode(
            WebDavSyncProfileEngineState(
              baseline: baseline,
              deferredCollectionLocal: local.encode(),
            ).toJson(),
          ),
        ),
      );
      final unchanged = build(
        {HomeCollectionInventory.prefsKey: local.encode(), 'theme': 'dark'},
        300,
        previous: persisted.baseline,
        deferred: persisted.deferredCollectionLocal,
      ).document;
      final key = WebDavSyncRecordKey.homeCollection('same');
      expect(
        (unchanged.watchState.records[key]!.value as Map)['title'],
        'Remote new',
      );
      expect(unchanged.watchState.records[key]!.stamp.normalizedTimeMs, 200);
      expect(
        unchanged.watchState.records,
        contains(WebDavSyncRecordKey.homeCollection('unseen')),
      );
      local.remove('same');
      final edited = build(
        {HomeCollectionInventory.prefsKey: local.encode()},
        400,
        previous: unchanged,
        deferred: persisted.deferredCollectionLocal,
      ).document;
      expect(edited.watchState.records[key]!.value, isNull);
      expect(edited.watchState.records[key]!.stamp.normalizedTimeMs, 400);
      expect(
        edited.watchState.records,
        contains(WebDavSyncRecordKey.homeCollection('unseen')),
      );
    },
  );
}
