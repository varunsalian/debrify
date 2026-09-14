import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Public StorageService contract on upstream/webdav-sync 077f2e79.
// Adapted from ba613d1a; run unchanged before and after extraction.
// Finite SDK transport observations, not serialized writes or UI search proof.
const _key = 'catalog_search_disabled_addons_v1';
const _limit = Duration(seconds: 5);

class _Backend extends InMemorySharedPreferencesStore {
  _Backend(super.data) : super.withData();
  final calls = <(String, String, Object?)>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('synthetic catalog preferences failure');
  bool holdRead = false;
  bool holdWrite = false;
  bool failRead = false;
  String outcome = 'ok';

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    if (holdRead) {
      entered.complete();
      await release.future.timeout(_limit);
    }
    if (failRead) throw failure;
    return super.getAllWithParameters(parameters);
  }

  Future<bool> finish(Future<bool> Function() persist) async {
    if (holdWrite) {
      entered.complete();
      await release.future.timeout(_limit);
    }
    if (outcome == 'throw') throw failure;
    if (outcome == 'false') return false;
    return persist();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) {
    calls.add(('set', key, value));
    return finish(() => super.setValue(type, key, value));
  }

  @override
  Future<bool> remove(String key) {
    calls.add(('remove', key, null));
    return finish(() => super.remove(key));
  }

  Future<Map<String, Object>> durable() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Backend backend;
  final a = ProfileScope(
    profileId: 'catalog-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'catalog-b',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  final other = ProfileScope(
    profileId: 'catalog-a',
    dataGeneration: 2,
    sessionEpoch: 3,
  );

  void install(Map<String, Object> data) {
    SharedPreferences.resetStatic();
    backend = _Backend({
      for (final e in data.entries) 'flutter.${e.key}': e.value,
      'flutter.catalog_sentinel': 'untouched',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  void profiles() {
    install({
      _key: '["legacy"]',
      a.preferenceKey(_key): '["a"]',
      b.preferenceKey(_key): '["b"]',
      other.preferenceKey(_key): '["other-generation"]',
    });
    ProfileRuntime.initializeCommitted(a);
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    install({});
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });

  test('absent returns independent mutable sets without writing', () async {
    final first = await StorageService.getCatalogSearchDisabledAddons();
    first.add('local-only');
    expect(await StorageService.getCatalogSearchDisabledAddons(), isEmpty);
    expect(backend.calls, isEmpty);
    expect((await backend.durable()).containsKey('flutter.$_key'), isFalse);
  });

  for (final raw in ['{', '{}', 'null', '42', '["valid",7]', '[null]']) {
    test(
      'JSON/list errors return whole empty without rewriting: $raw',
      () async {
        install({_key: raw});
        expect(await StorageService.getCatalogSearchDisabledAddons(), isEmpty);
        expect(backend.calls, isEmpty);
        expect((await backend.durable())['flutter.$_key'], raw);
      },
    );
  }

  for (final raw in <Object>[
    true,
    4,
    2.5,
    <String>['x'],
  ]) {
    test('physical ${raw.runtimeType} escapes JSON catch', () async {
      install({_key: raw});
      await expectLater(
        StorageService.getCatalogSearchDisabledAddons(),
        throwsA(isA<TypeError>()),
      );
      expect(backend.calls, isEmpty);
    });
  }

  test('SDK acquisition failure escapes getter catch', () async {
    backend.failRead = true;
    await expectLater(
      StorageService.getCatalogSearchDisabledAddons(),
      throwsA(same(backend.failure)),
    );
    expect(backend.calls, isEmpty);
  });

  test('dedup keeps first order and exact whitespace, no rewrite', () async {
    const raw = '[" z ","b"," z ","","B","b"]';
    install({_key: raw});
    expect((await StorageService.getCatalogSearchDisabledAddons()).toList(), [
      ' z ',
      'b',
      '',
      'B',
    ]);
    expect((await backend.durable())['flutter.$_key'], raw);
    expect(backend.calls, isEmpty);
  });

  test('setter encodes current insertion order without trimming', () async {
    await StorageService.setCatalogSearchDisabledAddons({' z ', '', 'b'});
    expect(backend.calls, [('set', 'flutter.$_key', '[" z ","","b"]')]);
    expect((await backend.durable())['flutter.catalog_sentinel'], 'untouched');
  });

  for (final empty in [false, true]) {
    for (final outcome in ['ok', 'false', 'throw']) {
      test(
        'held ${empty ? 'remove' : 'write'} $outcome preserves SDK cache versus durable result',
        () async {
          install({_key: '["old"]'});
          backend.holdWrite = true;
          backend.outcome = outcome;
          final result = StorageService.setCatalogSearchDisabledAddons(
            empty ? {} : {'new'},
          );
          final observed = expectLater(
            result,
            outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
          );
          await backend.entered.future.timeout(_limit);
          expect(backend.calls, [
            (
              empty ? 'remove' : 'set',
              'flutter.$_key',
              empty ? null : '["new"]',
            ),
          ]);
          expect((await backend.durable())['flutter.$_key'], '["old"]');
          backend.release.complete();
          await observed;
          expect(
            (await StorageService.getCatalogSearchDisabledAddons()).toList(),
            empty ? [] : ['new'],
          );
          final data = await backend.durable();
          if (outcome == 'ok' && empty) {
            expect(data.containsKey('flutter.$_key'), isFalse);
          } else {
            expect(
              data['flutter.$_key'],
              outcome == 'ok' ? '["new"]' : '["old"]',
            );
          }
          expect(data['flutter.catalog_sentinel'], 'untouched');
        },
      );
    }
  }

  for (final initiallyEmpty in [false, true]) {
    test(
      'caller live Set is read after held acquisition initiallyEmpty=$initiallyEmpty',
      () async {
        install({_key: '["old"]'});
        backend.holdRead = true;
        final live = initiallyEmpty ? <String>{} : {'before'};
        final result = StorageService.setCatalogSearchDisabledAddons(live);
        await backend.entered.future.timeout(_limit);
        live.clear();
        if (initiallyEmpty) live.addAll(['after', ' z ']);
        backend.release.complete();
        await result;
        expect(backend.calls, [
          (
            initiallyEmpty ? 'set' : 'remove',
            'flutter.$_key',
            initiallyEmpty ? '["after"," z "]' : null,
          ),
        ]);
      },
    );
  }

  for (final writing in [false, true]) {
    test('profile capture follows held acquisition writing=$writing', () async {
      profiles();
      backend.holdRead = true;
      final Future<Object?> result = writing
          ? StorageService.setCatalogSearchDisabledAddons({
              'new',
            }).then<Object?>((_) => null)
          : StorageService.getCatalogSearchDisabledAddons();
      await backend.entered.future.timeout(_limit);
      ProfileRuntime.publish(b);
      backend.release.complete();
      expect(await result, writing ? null : {'b'});
      final data = await backend.durable();
      expect(data['flutter.${a.preferenceKey(_key)}'], '["a"]');
      expect(
        data['flutter.${b.preferenceKey(_key)}'],
        writing ? '["new"]' : '["b"]',
      );
      expect(
        data['flutter.${other.preferenceKey(_key)}'],
        '["other-generation"]',
      );
      expect(data['flutter.$_key'], '["legacy"]');
    });
  }

  test(
    'read, write and empty removal belong only to the current generation',
    () async {
      profiles();
      expect(await StorageService.getCatalogSearchDisabledAddons(), {'a'});
      await StorageService.setCatalogSearchDisabledAddons({'changed-a'});
      expect(await StorageService.getCatalogSearchDisabledAddons(), {
        'changed-a',
      });
      await StorageService.setCatalogSearchDisabledAddons({});
      expect(await StorageService.getCatalogSearchDisabledAddons(), isEmpty);
      final data = await backend.durable();
      expect(data.containsKey('flutter.${a.preferenceKey(_key)}'), isFalse);
      expect(data['flutter.${b.preferenceKey(_key)}'], '["b"]');
      expect(
        data['flutter.${other.preferenceKey(_key)}'],
        '["other-generation"]',
      );
      expect(data['flutter.$_key'], '["legacy"]');
      expect(data['flutter.catalog_sentinel'], 'untouched');
      expect(backend.calls, [
        ('set', 'flutter.${a.preferenceKey(_key)}', '["changed-a"]'),
        ('remove', 'flutter.${a.preferenceKey(_key)}', null),
      ]);
      ProfileRuntime.publish(b);
      expect(await StorageService.getCatalogSearchDisabledAddons(), {'b'});
      ProfileRuntime.publish(other);
      expect(await StorageService.getCatalogSearchDisabledAddons(), {
        'other-generation',
      });
    },
  );

  for (final empty in [false, true]) {
    test(
      'in-flight ${empty ? 'remove' : 'write'} keeps its captured profile',
      () async {
        profiles();
        backend.holdWrite = true;
        final result = StorageService.setCatalogSearchDisabledAddons(
          empty ? {} : {'new-a'},
        );
        await backend.entered.future.timeout(_limit);
        ProfileRuntime.publish(b);
        backend.release.complete();
        await result;
        final data = await backend.durable();
        expect(
          data['flutter.${a.preferenceKey(_key)}'],
          empty ? null : '["new-a"]',
        );
        expect(data['flutter.${b.preferenceKey(_key)}'], '["b"]');
        expect(
          data['flutter.${other.preferenceKey(_key)}'],
          '["other-generation"]',
        );
        expect(data['flutter.$_key'], '["legacy"]');
        expect(backend.calls, [
          (
            empty ? 'remove' : 'set',
            'flutter.${a.preferenceKey(_key)}',
            empty ? null : '["new-a"]',
          ),
        ]);
        expect(await StorageService.getCatalogSearchDisabledAddons(), {'b'});
      },
    );
  }
}
