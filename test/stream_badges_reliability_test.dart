import 'dart:async';
import 'dart:convert';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:debrify/services/remote_control/remote_constants.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_active_profile_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String preset([int padding = 0]) => jsonEncode({
  'notes': 'x' * padding,
  'filters': [
    {'name': 'HDR', 'pattern': 'HDR'},
  ],
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = StreamBadgesService.instance;
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    ProfilePreferenceBudget.debugReset();
    svc.resetProfileScope();
  });
  tearDown(() {
    ProfilePreferenceBudget.debugReset();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    svc.resetProfileScope();
  });

  test(
    'corrupt sibling presets do not block unrelated removal or disabling',
    () async {
      SharedPreferences.setMockInitialValues({
        StreamBadgesService.sourcesKey: jsonEncode([
          StreamBadgeSource(id: 'bad', name: 'bad', json: 'broken').toJson(),
          StreamBadgeSource(id: 'one', name: 'one', json: preset()).toJson(),
          StreamBadgeSource(id: 'two', name: 'two', json: preset()).toJson(),
        ]),
      });
      await svc.setSourceEnabled('one', false);
      await svc.remove('two');
      final sources = await svc.getSources();
      expect(sources.map((s) => s.id), ['bad', 'one']);
      expect(sources.last.enabled, false);
      expect(sources.first.json, 'broken');
    },
  );
  test(
    'only enabled valid rules in enabled presets count toward the cap',
    () async {
      final large = jsonEncode({
        'filters': [
          for (var i = 0; i < 600; i++) {'name': '$i', 'pattern': 'HDR'},
        ],
      });
      SharedPreferences.setMockInitialValues({
        StreamBadgesService.sourcesKey: jsonEncode([
          StreamBadgeSource(
            id: 'disabled',
            name: 'disabled',
            json: large,
            enabled: false,
          ).toJson(),
        ]),
      });
      await svc.importJson(preset(), name: 'active');
      await svc.importJson(
        jsonEncode({
          'filters': [
            for (var i = 0; i < 600; i++)
              {'name': '$i', 'pattern': 'HDR', 'isEnabled': false},
          ],
        }),
        name: 'inactive rules',
      );
      expect(svc.matcher.value.rules, hasLength(1));
      await expectLater(
        svc.setSourceEnabled('disabled', true),
        throwsFormatException,
      );
      expect((await svc.getSources()).first.enabled, false);
    },
  );
  test(
    'unchanged preferences preserve the live matcher across refreshes',
    () async {
      await svc.importJson(preset(), name: 'one');
      final matcher = svc.matcher.value;
      await svc.refreshFromPreferences();
      await svc.refreshFromPreferences();
      expect(identical(svc.matcher.value, matcher), true);
    },
  );
  test(
    'concurrent imports preserve both inventories across service instances',
    () async {
      final other = StreamBadgesService();
      await Future.wait([
        svc.importJson(preset(), name: 'one'),
        other.importJson(preset(), name: 'two'),
      ]);
      expect(await svc.getSources(), hasLength(2));
    },
  );
  test(
    'aggregate rule limit rejects imports without changing saved presets',
    () async {
      await svc.importJson(preset(), name: 'original');
      await expectLater(
        svc.importJson(
          jsonEncode({
            'filters': [
              for (var i = 0; i < 512; i++)
                {'name': 'Rule $i', 'pattern': 'HDR'},
            ],
          }),
          name: 'too many',
        ),
        throwsFormatException,
      );
      expect((await svc.getSources()).single.name, 'original');
      expect(svc.matcher.value.rules, hasLength(1));
    },
  );
  test('oversized existing inventories can be reduced in stages', () async {
    SharedPreferences.setMockInitialValues({
      StreamBadgesService.sourcesKey: jsonEncode([
        for (var i = 0; i < 3; i++)
          StreamBadgeSource(
            id: '$i',
            name: '$i',
            json: jsonEncode({
              'filters': [
                for (var j = 0; j < 300; j++) {'name': '$j', 'pattern': 'x'},
              ],
            }),
          ).toJson(),
      ]),
    });
    await svc.warmUp();
    expect(svc.matcher.value.failed, true);
    await svc.remove('0');
    expect(await svc.getSources(), hasLength(2));
    expect(svc.matcher.value.failed, true);
    await svc.remove('1');
    expect(svc.matcher.value.failed, false);
    expect(svc.matcher.value.rules, hasLength(300));
  });
  test('multiple presets exceeding 128 KiB persist and reload', () async {
    await svc.importJson(preset(70 * 1024), name: 'one');
    await svc.importJson(preset(70 * 1024), name: 'two');
    await svc.importJson(preset(1100 * 1024), name: 'large');
    svc.resetProfileScope();
    await svc.warmUp();
    final sources = await svc.getSources();
    expect(sources.map((s) => s.name), ['one', 'two', 'large']);
    expect(sources.last.json, preset(1100 * 1024));
    expect(svc.matcher.value.rules, hasLength(3));
  });
  test('backup string limit rejects aggregate growth atomically', () async {
    await svc.importJson(preset(2200 * 1024), name: 'one');
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(StreamBadgesService.sourcesKey);
    await expectLater(
      svc.importJson(preset(2200 * 1024), name: 'two'),
      throwsFormatException,
    );
    expect(prefs.getString(StreamBadgesService.sourcesKey), before);
    expect((await svc.getSources()).single.name, 'one');
    expect(svc.matcher.value.rules, hasLength(1));
    await expectLater(
      svc.applyBackup([
        StreamBadgeSource(
          id: 'two',
          name: 'two',
          json: preset(2200 * 1024),
        ).toJson(),
      ]),
      throwsFormatException,
    );
    expect(prefs.getString(StreamBadgesService.sourcesKey), before);
  });

  test('stored size includes JSON escaping beyond the import size', () async {
    final escaped = jsonEncode({
      'notes': List.filled(1500 * 1024, '\n').join(),
      'filters': [
        {'name': 'HDR', 'pattern': 'HDR'},
      ],
    });
    await expectLater(
      svc.importJson(escaped, name: 'escaped'),
      throwsFormatException,
    );
    expect(await svc.getSources(), isEmpty);
  });

  test(
    'existing inventories above backup limit can shrink in stages',
    () async {
      SharedPreferences.setMockInitialValues({
        StreamBadgesService.sourcesKey: jsonEncode([
          for (var i = 0; i < 3; i++)
            StreamBadgeSource(
              id: '$i',
              name: '$i',
              json: preset(2200 * 1024),
            ).toJson(),
        ]),
      });
      await svc.remove('0');
      expect(await svc.getSources(), hasLength(2));
      await svc.remove('1');
      expect((await svc.getSources()).single.id, '2');
    },
  );
  test(
    'refused TV persistence never publishes or reports a successful import',
    () async {
      ProfilePreferenceBudget.debugEnforcedOverride = true;
      SharedPreferences.setMockInitialValues({'full': 'x' * (512 * 1024)});
      await svc.warmUp();
      await expectLater(
        svc.importJson(preset(), name: 'one'),
        throwsStateError,
      );
      expect(await svc.getSources(), isEmpty);
      expect(svc.matcher.value.isEmpty, true);
    },
  );
  test('refused master setting does not change its live value', () async {
    ProfilePreferenceBudget.debugEnforcedOverride = true;
    SharedPreferences.setMockInitialValues({'full': 'x' * (512 * 1024)});
    await svc.warmUp();
    await expectLater(svc.setEnabled(false), throwsStateError);
    expect(svc.enabled, true);
  });
  test('pending URL import cannot cross a profile switch', () async {
    final a = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final b = ProfileScope(
      profileId: 'two',
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileRuntime.initializeCommitted(a);
    final started = Completer<void>(), reply = Completer<http.Response>();
    final service = StreamBadgesService(
      httpClientFactory: () => MockClient((_) {
        started.complete();
        return reply.future;
      }),
    );
    final pending = service.importFromUrl(
      'https://example.invalid/badges.json',
    );
    final rejected = expectLater(pending, throwsStateError);
    await started.future;
    ProfileRuntime.publish(b);
    service.resetProfileScope();
    await service.warmUp();
    reply.complete(http.Response(preset(), 200));
    await rejected;
    expect(await service.getSources(), isEmpty);
    expect(service.matcher.value.isEmpty, true);
  });
  test('refresh cannot recreate a deleted preset', () async {
    final reply = Completer<http.Response>(), started = Completer<void>();
    final service = StreamBadgesService(
      httpClientFactory: () => MockClient((_) {
        started.complete();
        return reply.future;
      }),
    );
    final item = await service.importJson(
      preset(),
      name: 'one',
      url: 'https://example.invalid/badges.json',
    );
    final pending = service.refresh(item.source.id);
    final rejected = expectLater(pending, throwsStateError);
    await started.future;
    await service.remove(item.source.id);
    reply.complete(http.Response(preset(), 200));
    await rejected;
    expect(await service.getSources(), isEmpty);
  });
  test(
    'inactive restore cannot publish its matcher into active profile',
    () async {
      final a = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final b = ProfileScope(
        profileId: 'two',
        dataGeneration: 1,
        sessionEpoch: 0,
      );
      ProfileRuntime.initializeCommitted(a);
      await svc.warmUp();
      await ProfileRuntime.withCapturedScope(
        b,
        () => svc.importJson(preset(), name: 'inactive'),
      );
      expect(svc.matcher.value.isEmpty, true);
      expect(await svc.getSources(), isEmpty);
    },
  );
  test(
    'WebDAV refresh applies both source and master changes to live matcher',
    () async {
      await svc.warmUp();
      await svc.importJson(preset(), name: 'one');
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(StreamBadgesService.enabledKey, false);
      await const DefaultWebDavSyncActiveProfileRefresher().refresh({
        StreamBadgesService.enabledKey,
      }, authorizationBarrier: () {});
      expect(svc.matcher.value.isEmpty, true);
      expect(svc.enabled, false);
      await prefs.setBool(StreamBadgesService.enabledKey, true);
      await prefs.setString(StreamBadgesService.sourcesKey, '[]');
      await const DefaultWebDavSyncActiveProfileRefresher().refresh({
        StreamBadgesService.sourcesKey,
        StreamBadgesService.enabledKey,
      }, authorizationBarrier: () {});
      expect(svc.enabled, true);
      expect(svc.matcher.value.isEmpty, true);
    },
  );
  test(
    'sync refresh never deadlocks behind a writer waiting for its barrier',
    () async {
      await svc.warmUp();
      final entered = Completer<void>(), writing = Completer<void>();
      final guarded = ProfilePreferences.captureMutationSnapshot((_) async {
        entered.complete();
        await writing.future;
        await const DefaultWebDavSyncActiveProfileRefresher().refresh({
          StreamBadgesService.sourcesKey,
        }, authorizationBarrier: () {});
      });
      await entered.future;
      final pending = svc.importJson(preset(), name: 'one');
      await Future<void>.delayed(Duration.zero);
      writing.complete();
      await Future.wait([guarded, pending]).timeout(const Duration(seconds: 2));
      expect(await svc.getSources(), hasLength(1));
    },
  );
  test('atomic import reads the value after a queued sync apply', () async {
    final entered = Completer<void>(), resume = Completer<void>();
    final existing = StreamBadgeSource(
      id: 'remote',
      name: 'remote',
      json: preset(),
    ).toJson();
    final guarded = ProfilePreferences.captureMutationSnapshot((_) async {
      entered.complete();
      await resume.future;
      final raw = await SharedPreferences.getInstance();
      await raw.setString(
        StreamBadgesService.sourcesKey,
        jsonEncode([existing]),
      );
    });
    await entered.future;
    final pending = svc.importJson(preset(), name: 'local');
    await Future<void>.delayed(Duration.zero);
    resume.complete();
    await Future.wait([guarded, pending]);
    expect(await svc.getSources(), hasLength(2));
  });
  test('new sender emits plain source entries for older receivers', () async {
    await svc.importJson(preset(), name: 'one');
    await svc.setEnabled(false);
    final payload = await svc.exportTransferJson(peerProtocolVersion: 6);
    // This is the source-entry decoder used by legacy receivers: envelopes
    // would decode to null and produce "one rejected, nothing added".
    final legacySources = payload.map(StreamBadgeSource.fromJson).toList();
    expect(legacySources, hasLength(1));
    expect(legacySources.single?.name, 'one');
    expect(payload.single.containsKey('badgeTransferVersion'), false);
    expect(payload, await svc.exportJson());
    SharedPreferences.setMockInitialValues({});
    svc.resetProfileScope();
    final result = await svc.applyBackup(payload);
    expect(result.imported, 1);
    expect(result.failed, 0);
    expect(svc.enabled, true); // Legacy format leaves the receiver's setting.
  });

  test('selective transfer preserves a disabled master switch', () async {
    await svc.importJson(preset(), name: 'one');
    await svc.setEnabled(false);
    final payload = await svc.exportTransferJson(
      peerProtocolVersion: kProtoVersion,
    );
    SharedPreferences.setMockInitialValues({});
    svc.resetProfileScope();
    await svc.warmUp();
    final result = await svc.applyBackup(payload);
    expect(result.imported, 1);
    expect(svc.enabled, false);
    expect(svc.matcher.value.isEmpty, true);
  });
  test(
    'legacy source arrays preserve the destination master setting',
    () async {
      await svc.setEnabled(false);
      await svc.applyBackup([
        StreamBadgeSource(id: 'one', name: 'one', json: preset()).toJson(),
      ]);
      expect(svc.enabled, false);
      expect(await svc.getSources(), hasLength(1));
    },
  );
  test('backup restores presets above the former size cap', () async {
    await svc.importJson(preset(), name: 'one');
    final result = await svc.applyBackup([
      StreamBadgeSource(
        id: 'two',
        name: 'two',
        json: preset(200 * 1024),
      ).toJson(),
    ]);
    expect(result.imported, 1);
    expect((await svc.getSources()).map((s) => s.name), contains('two'));
  });
  test(
    'corrupt inventory is an error rather than an empty overwrite',
    () async {
      SharedPreferences.setMockInitialValues({
        StreamBadgesService.sourcesKey: 'broken',
      });
      await expectLater(
        svc.importJson(preset(), name: 'one'),
        throwsFormatException,
      );
      expect(
        (await SharedPreferences.getInstance()).getString(
          StreamBadgesService.sourcesKey,
        ),
        'broken',
      );
    },
  );
  test(
    'corrupt optional presets do not block startup and can be reset',
    () async {
      SharedPreferences.setMockInitialValues({
        StreamBadgesService.sourcesKey: 'broken',
      });
      await svc.warmUp();
      expect(svc.matcher.value.isEmpty, true);
      await svc.clear();
      expect(await svc.getSources(), isEmpty);
      await svc.importJson(preset(), name: 'recovered');
      expect(svc.matcher.value.isEmpty, false);
    },
  );
}
