import 'dart:async';
import 'dart:convert';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

// Public API characterization pinned on upstream 75b53ef3 before extraction.
// Reset captures one profile for all five filters AND the provider removal.
final filterDefaultCases =
    <
      ({
        String key,
        Future<List<String>> Function() read,
        Future<void> Function(List<String>) write,
      })
    >[
      (
        key: 'default_filter_qualities_v1',
        read: StorageService.getDefaultFilterQualities,
        write: StorageService.setDefaultFilterQualities,
      ),
      (
        key: 'default_filter_rip_sources_v1',
        read: StorageService.getDefaultFilterRipSources,
        write: StorageService.setDefaultFilterRipSources,
      ),
      (
        key: 'default_filter_languages_v1',
        read: StorageService.getDefaultFilterLanguages,
        write: StorageService.setDefaultFilterLanguages,
      ),
      (
        key: 'default_filter_sizes_v1',
        read: StorageService.getDefaultFilterSizes,
        write: StorageService.setDefaultFilterSizes,
      ),
      (
        key: 'default_filter_dynamic_ranges_v1',
        read: StorageService.getDefaultFilterDynamicRanges,
        write: StorageService.setDefaultFilterDynamicRanges,
      ),
    ];

const _provider = 'default_torrent_provider_v1';
const _sentinels = <String, Object>{
  'quick_play_honors_filters_v1': false,
  'quick_play_movie_rules_v2': '{"keep":"movie"}',
  'quick_play_series_rules_v2': '{"keep":"series"}',
  'debrify_tv_filter_qualities_v1': '["tv-only"]',
  'engine_enabled': true,
  'unrelated_filter_sentinel': 'untouched',
};

class _Backend extends InMemorySharedPreferencesStore {
  _Backend(super.data) : super.withData();
  final attempts = <String>[];
  final failure = StateError('synthetic filter persistence failure');
  String? affectedKey;
  String outcome = 'ok';
  bool hold = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  Future<bool> _attempt(
    String verb,
    String key,
    Future<bool> Function() commit,
  ) async {
    attempts.add('$verb:$key');
    if (key == affectedKey) {
      if (hold) {
        entered.complete();
        await release.future;
      }
      if (outcome == 'throw') throw failure;
      if (outcome == 'false') return false;
    }
    return commit();
  }

  @override
  Future<bool> remove(String key) =>
      _attempt('remove', key, () => super.remove(key));

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _attempt('set', key, () => super.setValue(valueType, key, value));

  Future<Map<String, Object>> snapshot() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final keys = filterDefaultCases.map((e) => e.key).toList();
  final ordered = [...keys, _provider];
  final expected = <String, Object>{
    for (final key in keys) key: '["first","second","first"]',
    _provider: 'torbox',
    ..._sentinels,
  };
  final a = ProfileScope(
    profileId: 'filter-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'filter-b',
    dataGeneration: 2,
    sessionEpoch: 2,
  );
  late _Backend backend;
  late SharedPreferencesStorePlatform previous;
  final signals = <String>[];

  void install({bool committed = false}) {
    SharedPreferences.resetStatic();
    backend = _Backend({
      if (!committed)
        for (final e in expected.entries) 'flutter.${e.key}': e.value,
      if (committed)
        for (final scope in [a, b])
          for (final e in expected.entries)
            'flutter.${scope.preferenceKey(e.key)}': e.value,
    });
    SharedPreferencesStorePlatform.instance = backend;
    if (committed) ProfileRuntime.initializeCommitted(a);
    signals.clear();
  }

  void expectUntouched(Map<String, Object> durable, {required bool committed}) {
    for (final e in _sentinels.entries) {
      expect(
        durable['flutter.${committed ? a.preferenceKey(e.key) : e.key}'],
        e.value,
      );
    }
    if (committed) {
      for (final e in expected.entries) {
        expect(durable['flutter.${b.preferenceKey(e.key)}'], e.value);
      }
    }
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfilePreferences.debugResetMutationTracking();
    ProfileRuntime.initializeLegacy();
    ProfilePreferences.webDavSyncLocalChangeSink = (id, key) =>
        signals.add('$id:$key');
    install();
  });
  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    ProfileRuntime.debugReset();
  });

  for (final entry in filterDefaultCases) {
    test(
      '${entry.key}: absent, JSON order/duplicates and empty write',
      () async {
        final raw = await SharedPreferences.getInstance();
        await raw.remove(entry.key);
        expect(await entry.read(), isEmpty);
        backend.attempts.clear();
        await entry.write(['first', 'second', 'first']);
        expect(raw.get(entry.key), expected[entry.key]);
        expect(await entry.read(), ['first', 'second', 'first']);
        await entry.write([]);
        expect(raw.get(entry.key), '[]');
        expect(await entry.read(), isEmpty);
        expect(backend.attempts, [
          'set:flutter.${entry.key}',
          'set:flutter.${entry.key}',
        ]);
        expectUntouched(await backend.snapshot(), committed: false);
      },
    );

    test(
      '${entry.key}: malformed data throws without repairing bytes',
      () async {
        final raw = await SharedPreferences.getInstance();
        for (final value in ['[', '{}', '[1]', 'null', '"text"']) {
          await raw.setString(entry.key, value);
          backend.attempts.clear();
          await expectLater(
            entry.read(),
            value == '['
                ? throwsA(isA<FormatException>())
                : throwsA(isA<TypeError>()),
          );
          expect(raw.get(entry.key), value);
          expect(backend.attempts, isEmpty);
        }
        await raw.setStringList(entry.key, ['wrong physical type']);
        backend.attempts.clear();
        await expectLater(entry.read(), throwsA(isA<TypeError>()));
        expect(raw.get(entry.key), ['wrong physical type']);
        expect(backend.attempts, isEmpty);
      },
    );

    for (final outcome in ['ok', 'false', 'throw']) {
      test(
        '${entry.key}: committed write $outcome preserves cache, durability and sync',
        () async {
          install(committed: true);
          final raw = await SharedPreferences.getInstance();
          backend.affectedKey = 'flutter.${a.preferenceKey(entry.key)}';
          backend.outcome = outcome;
          await expectLater(
            entry.write(['new', 'new']),
            outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
          );
          expect(raw.get(a.preferenceKey(entry.key)), '["new","new"]');
          final durable = await backend.snapshot();
          expect(
            durable[backend.affectedKey],
            outcome == 'ok' ? '["new","new"]' : expected[entry.key],
          );
          expect(backend.attempts, ['set:${backend.affectedKey}']);
          expect(
            signals,
            outcome == 'ok' ? ['${a.profileId}:${entry.key}'] : isEmpty,
          );
          expectUntouched(durable, committed: true);
        },
      );
    }
  }

  for (final committed in [false, true]) {
    test(
      'reset single capture and exact order; committed $committed',
      () async {
        install(committed: committed);
        await StorageService.clearAllFilterSettings();
        expect(
          backend.attempts,
          ordered.map(
            (k) => 'remove:flutter.${committed ? a.preferenceKey(k) : k}',
          ),
        );
        final durable = await backend.snapshot();
        for (final key in ordered) {
          expect(
            durable.containsKey(
              'flutter.${committed ? a.preferenceKey(key) : key}',
            ),
            isFalse,
          );
        }
        expect(
          signals,
          committed ? ordered.map((k) => '${a.profileId}:$k') : isEmpty,
        );
        expectUntouched(durable, committed: committed);
      },
    );

    for (var index = 0; index < ordered.length; index++) {
      for (final outcome in ['false', 'throw']) {
        test(
          'reset $outcome at $index; committed $committed preserves exact durable prefix',
          () async {
            install(committed: committed);
            final raw = await SharedPreferences.getInstance();
            String physical(String k) => committed ? a.preferenceKey(k) : k;
            backend.affectedKey = 'flutter.${physical(ordered[index])}';
            backend.outcome = outcome;
            await expectLater(
              StorageService.clearAllFilterSettings(),
              outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
            );
            final count = outcome == 'throw' ? index + 1 : ordered.length;
            expect(
              backend.attempts,
              ordered.take(count).map((k) => 'remove:flutter.${physical(k)}'),
            );
            final durable = await backend.snapshot();
            for (var i = 0; i < ordered.length; i++) {
              expect(
                durable.containsKey('flutter.${physical(ordered[i])}'),
                i == index || (outcome == 'throw' && i > index),
              );
              expect(raw.containsKey(physical(ordered[i])), i >= count);
            }
            expect(
              signals,
              committed
                  ? [
                      for (var i = 0; i < count; i++)
                        if (i != index) '${a.profileId}:${ordered[i]}',
                    ]
                  : isEmpty,
            );
            expectUntouched(durable, committed: committed);
          },
        );
      }
    }
  }

  for (var index = 0; index < ordered.length; index++) {
    for (final outcome in ['ok', 'false', 'throw']) {
      test(
        'profile switch during reset $index/$outcome never reacquires provider on B',
        () async {
          install(committed: true);
          backend.affectedKey = 'flutter.${a.preferenceKey(ordered[index])}';
          backend.outcome = outcome;
          backend.hold = true;
          final pending = StorageService.clearAllFilterSettings();
          final observed = expectLater(
            pending,
            outcome == 'throw'
                ? throwsA(same(backend.failure))
                : index < ordered.length - 1
                ? throwsA(isA<StateError>())
                : completes,
          );
          await backend.entered.future.timeout(const Duration(seconds: 2));
          ProfileRuntime.publish(b);
          backend.release.complete();
          await observed;
          expect(
            backend.attempts,
            ordered
                .take(index + 1)
                .map((k) => 'remove:flutter.${a.preferenceKey(k)}'),
          );
          final durable = await backend.snapshot();
          for (var i = 0; i < ordered.length; i++) {
            expect(
              durable.containsKey('flutter.${a.preferenceKey(ordered[i])}'),
              i > index || (i == index && outcome != 'ok'),
            );
          }
          expect(signals, [
            for (var i = 0; i <= index; i++)
              if (i < index || outcome == 'ok') '${a.profileId}:${ordered[i]}',
          ]);
          expectUntouched(durable, committed: true);
          for (final entry in filterDefaultCases) {
            expect(
              await entry.read(),
              jsonDecode(expected[entry.key]! as String),
            );
          }
        },
      );
    }
  }
}
