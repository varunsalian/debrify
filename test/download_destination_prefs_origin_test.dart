import 'dart:async';

import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Public StorageService contract on upstream/webdav-sync 077f2e79.
// Adapted from 067cb6a2; run unchanged before and after extraction.
// Preference transport only: no picker, SAF grant, filesystem or native proof.
const _limit = Duration(seconds: 5);
const _uri = 'download_tree_uri_v1';
const _name = 'download_tree_display_name_v1';
const _path = 'download_dir_path_v1';
const _keys = [_uri, _name, _path];
const _initial = {_uri: 'old-uri', _name: 'old-name', _path: 'old-path'};
const _updated = {
  _uri: '  synthetic-uri  ',
  _name: '  synthetic-name  ',
  _path: '  synthetic-path  ',
};

class _DestinationBackend extends InMemorySharedPreferencesStore {
  _DestinationBackend(super.data) : super.withData();

  final attempts = <String>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('synthetic destination transport failure');
  int? holdAt;
  int? failAt;
  bool returnFalse = false;

  Future<bool> _attempt(
    String operation,
    Future<bool> Function() persist,
  ) async {
    final index = attempts.length;
    attempts.add(operation);
    if (index == holdAt) {
      entered.complete();
      await release.future.timeout(_limit);
    }
    if (index == failAt) {
      if (returnFalse) return false;
      throw failure;
    }
    return persist();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) =>
      _attempt('set:$key', () => super.setValue(type, key, value));

  @override
  Future<bool> remove(String key) =>
      _attempt('remove:$key', () => super.remove(key));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _DestinationBackend backend;
  final a = ProfileScope(
    profileId: 'destination-a',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'destination-b',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  final oldGeneration = ProfileScope(
    profileId: 'destination-a',
    dataGeneration: 2,
    sessionEpoch: 3,
  );
  final readers = <String, Future<String?> Function()>{
    _uri: StorageService.getDownloadTreeUri,
    _name: StorageService.getDownloadTreeDisplayName,
    _path: StorageService.getDownloadDirPath,
  };
  final operations =
      <
        ({
          String label,
          List<String> keys,
          Future<void> Function() run,
          bool clear,
        })
      >[
        (
          label: 'set tree',
          keys: [_uri, _name],
          run: () => StorageService.setDownloadTreeUri(
            _updated[_uri]!,
            _updated[_name]!,
          ),
          clear: false,
        ),
        (
          label: 'clear tree',
          keys: [_uri, _name],
          run: StorageService.clearDownloadTreeUri,
          clear: true,
        ),
        (
          label: 'set path',
          keys: [_path],
          run: () => StorageService.setDownloadDirPath(_updated[_path]!),
          clear: false,
        ),
        (
          label: 'clear path',
          keys: [_path],
          run: StorageService.clearDownloadDirPath,
          clear: true,
        ),
      ];

  void install(Map<String, Object> values) {
    SharedPreferences.resetStatic();
    backend = _DestinationBackend({
      for (final e in values.entries) 'flutter.${e.key}': e.value,
      'flutter.destination_sentinel': 'untouched',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    install(_initial);
  });

  tearDown(() {
    if (!backend.release.isCompleted) backend.release.complete();
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    ProfileRuntime.debugReset();
  });

  for (final entry in readers.entries) {
    test(
      '${entry.key}: absent/empty only normalize; raw whitespace and wrong types remain observable',
      () async {
        for (final value in <Object?>[
          null,
          '',
          ' ',
          '\t\n',
          '  synthetic value  ',
          7,
          false,
          <String>['not a String'],
        ]) {
          install({if (value != null) entry.key: value});
          final before = await backend.getAll();
          if (value != null && value is! String) {
            await expectLater(entry.value(), throwsA(isA<TypeError>()));
          } else {
            expect(await entry.value(), value == '' ? null : value);
          }
          expect(await backend.getAll(), before);
          expect(backend.attempts, isEmpty);
        }
      },
    );
  }

  test('empty strings are physically written rather than removed', () async {
    await StorageService.setDownloadTreeUri('', '');
    await StorageService.setDownloadDirPath('');
    final prefs = await SharedPreferences.getInstance();
    for (final key in _keys) {
      expect(prefs.containsKey(key), isTrue);
      expect(prefs.get(key), '');
      expect(await readers[key]!(), isNull);
    }
  });

  test(
    'committed defaults never fall back to legacy destination strings',
    () async {
      ProfileRuntime.initializeCommitted(a);
      for (final reader in readers.values) {
        expect(await reader(), isNull);
      }
      expect(backend.attempts, isEmpty);
    },
  );

  test(
    'normal reads, writes and clears isolate profiles and generations',
    () async {
      install({
        ..._initial,
        for (final scope in [a, b, oldGeneration])
          for (final entry in _initial.entries)
            scope.preferenceKey(entry.key): entry.value,
      });
      ProfileRuntime.initializeCommitted(a);
      await StorageService.setDownloadTreeUri(
        _updated[_uri]!,
        _updated[_name]!,
      );
      await StorageService.setDownloadDirPath(_updated[_path]!);
      for (final entry in readers.entries) {
        expect(await entry.value(), _updated[entry.key]);
      }
      await StorageService.clearDownloadTreeUri();
      await StorageService.clearDownloadDirPath();
      final persisted = await backend.getAll();
      for (final entry in readers.entries) {
        expect(await entry.value(), isNull);
        expect(
          persisted.containsKey('flutter.${a.preferenceKey(entry.key)}'),
          isFalse,
        );
        expect(persisted['flutter.${entry.key}'], _initial[entry.key]);
        for (final scope in [b, oldGeneration]) {
          expect(
            persisted['flutter.${scope.preferenceKey(entry.key)}'],
            _initial[entry.key],
          );
        }
      }
      for (final scope in [b, oldGeneration]) {
        ProfileRuntime.publish(scope);
        for (final entry in readers.entries) {
          expect(await entry.value(), _initial[entry.key]);
        }
      }
    },
  );

  for (final op in operations) {
    for (var position = 0; position < op.keys.length; position++) {
      for (final outcome in ['ok', 'false', 'throw']) {
        test(
          '${op.label}: held operation $position/$outcome preserves order, cache and durable differences',
          () async {
            final prefs = await SharedPreferences.getInstance();
            backend.holdAt = position;
            backend.failAt = outcome == 'ok' ? null : position;
            backend.returnFalse = outcome == 'false';
            final future = op.run();
            final observed = expectLater(
              future,
              outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
            );
            await backend.entered.future.timeout(_limit);
            final attempted = op.keys.take(position + 1).toList();
            final prefix = op.clear ? 'remove' : 'set';
            expect(
              backend.attempts,
              attempted.map((k) => '$prefix:flutter.$k'),
            );
            // The SDK cache changes before its platform write completes.
            for (final key in attempted) {
              expect(prefs.get(key), op.clear ? null : _updated[key]);
            }
            final held = await backend.getAll();
            expect(
              held['flutter.${op.keys[position]}'],
              _initial[op.keys[position]],
            );
            backend.release.complete();
            await observed;
            final count = outcome == 'throw' ? position + 1 : op.keys.length;
            expect(
              backend.attempts,
              op.keys.take(count).map((k) => '$prefix:flutter.$k'),
            );
            final persisted = await backend.getAll();
            for (final key in _keys) {
              final index = op.keys.indexOf(key);
              final attemptedKey = index >= 0 && index < count;
              final committed =
                  attemptedKey && (outcome == 'ok' || index != position);
              expect(
                prefs.get(key),
                attemptedKey
                    ? (op.clear ? null : _updated[key])
                    : _initial[key],
              );
              expect(
                persisted['flutter.$key'],
                committed ? (op.clear ? null : _updated[key]) : _initial[key],
              );
            }
            expect(persisted['flutter.destination_sentinel'], 'untouched');
          },
        );
      }
    }

    for (var position = 0; position < op.keys.length; position++) {
      test(
        '${op.label}: profile switch at held operation $position keeps in-flight old write and rejects later stale use',
        () async {
          install({
            ..._initial,
            for (final scope in [a, b, oldGeneration])
              for (final e in _initial.entries)
                scope.preferenceKey(e.key): e.value,
          });
          ProfileRuntime.initializeCommitted(a);
          final prefs = await SharedPreferences.getInstance();
          backend.holdAt = position;
          final future = op.run();
          final hasLater = position + 1 < op.keys.length;
          final observed = expectLater(
            future,
            hasLater ? throwsA(isA<StateError>()) : completes,
          );
          await backend.entered.future.timeout(_limit);
          ProfileRuntime.publish(b);
          backend.release.complete();
          await observed;
          final changed = op.keys.take(position + 1).toSet();
          final prefix = op.clear ? 'remove' : 'set';
          expect(
            backend.attempts,
            op.keys
                .take(position + 1)
                .map((k) => '$prefix:flutter.${a.preferenceKey(k)}'),
          );
          final persisted = await backend.getAll();
          for (final key in _keys) {
            expect(
              prefs.get(a.preferenceKey(key)),
              changed.contains(key)
                  ? (op.clear ? null : _updated[key])
                  : _initial[key],
            );
            expect(
              persisted['flutter.${a.preferenceKey(key)}'],
              changed.contains(key)
                  ? (op.clear ? null : _updated[key])
                  : _initial[key],
            );
            for (final scope in [b, oldGeneration]) {
              expect(
                persisted['flutter.${scope.preferenceKey(key)}'],
                _initial[key],
              );
            }
            expect(persisted['flutter.$key'], _initial[key]);
            expect(await readers[key]!(), _initial[key]);
          }
          expect(persisted['flutter.destination_sentinel'], 'untouched');
        },
      );
    }
  }
}
