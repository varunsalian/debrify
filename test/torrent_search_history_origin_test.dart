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

// Public API characterization pinned before extraction on upstream 75b53ef3.
// No live history capture, serialization or profile-safety claim.
const _history = 'torrent_search_history_v1';
const _enabled = 'torrent_search_history_enabled';

class _Backend extends InMemorySharedPreferencesStore {
  _Backend(super.data) : super.withData();
  final writes = <String>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  final failure = StateError('synthetic history failure');
  bool holdRead = false;
  bool failRead = false;
  bool holdWrite = false;
  String outcome = 'ok';
  int reads = 0;

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) async {
    reads++;
    if (holdRead) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    if (failRead) throw failure;
    return super.getAllWithParameters(parameters);
  }

  Future<bool> _attempt(String key, Future<bool> Function() commit) async {
    writes.add(key);
    if (holdWrite) {
      entered.complete();
      await release.future;
    }
    if (outcome == 'throw') throw failure;
    if (outcome == 'false') return false;
    return commit();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _attempt('set:$key', () => super.setValue(valueType, key, value));

  @override
  Future<bool> remove(String key) =>
      _attempt('remove:$key', () => super.remove(key));

  Future<void> seed(String key, Object value) async {
    await super.setValue('String', 'flutter.$key', value);
  }

  Future<Map<String, Object>> snapshot() => super.getAllWithParameters(
    GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
  );
}

Map<String, dynamic> _row(String hash, {String service = 'old'}) => {
  'torrent': {'infohash': hash, 'name': 'synthetic-$hash'},
  'service': service,
  'clickedAt': 1,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform previous;
  late _Backend backend;
  void install(Map<String, Object> values) {
    SharedPreferences.resetStatic();
    backend = _Backend({
      for (final e in values.entries) 'flutter.${e.key}': e.value,
      'flutter.history_sentinel': 'untouched',
    });
    SharedPreferencesStorePlatform.instance = backend;
  }

  setUp(() {
    previous = SharedPreferencesStorePlatform.instance;
    ProfileRuntime.debugReset();
    ProfilePreferences.debugResetMutationTracking();
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    ProfileRuntime.initializeLegacy();
    install({});
  });
  tearDown(() async {
    if (!backend.release.isCompleted) backend.release.complete();
    try {
      expect(
        (await backend.snapshot())['flutter.history_sentinel'],
        'untouched',
      );
    } finally {
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = previous;
      ProfileRuntime.debugReset();
      ProfilePreferences.webDavSyncLocalChangeSink = null;
    }
  });

  test('absent defaults: empty history and enabled, no writes', () async {
    expect(await StorageService.getTorrentSearchHistory(), isEmpty);
    expect(await StorageService.getTorrentSearchHistoryEnabled(), isTrue);
    expect(backend.writes, isEmpty);
  });

  for (final raw in ['', '[', '{}', 'null', '7', '"text"']) {
    test('malformed or non-list JSON $raw is not repaired', () async {
      install({_history: raw});
      expect(await StorageService.getTorrentSearchHistory(), isEmpty);
      expect((await SharedPreferences.getInstance()).get(_history), raw);
      expect(backend.writes, isEmpty);
    });
  }

  for (final key in [_history, _enabled]) {
    test('wrong physical type escapes outside decode catch: $key', () async {
      install({key: 7});
      await expectLater(
        key == _history
            ? StorageService.getTorrentSearchHistory()
            : StorageService.getTorrentSearchHistoryEnabled(),
        throwsA(isA<TypeError>()),
      );
      expect(backend.writes, isEmpty);
    });
  }

  test(
    'reader keeps map order and nested types, returns fresh decoded rows',
    () async {
      final rows = [
        null,
        3,
        _row('b'),
        ['ignored'],
        {'arbitrary': true},
        _row('a'),
      ];
      final raw = jsonEncode(rows);
      install({_history: raw});
      final read = await StorageService.getTorrentSearchHistory();
      expect(read, [
        _row('b'),
        {'arbitrary': true},
        _row('a'),
      ]);
      (read.first['torrent'] as Map)['name'] = 'changed in caller';
      expect(await StorageService.getTorrentSearchHistory(), [
        _row('b'),
        {'arbitrary': true},
        _row('a'),
      ]);
      expect((await SharedPreferences.getInstance()).getString(_history), raw);
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'exact hash dedup across services, latest first, max five even disabled',
    () async {
      install({
        _history: jsonEncode([
          _row('same'),
          _row('SAME'),
          _row('b'),
          _row('same', service: 'other'),
          _row('c'),
          _row('d'),
          _row('e'),
        ]),
        _enabled: false,
      });
      final before = DateTime.now().millisecondsSinceEpoch;
      await StorageService.addTorrentToHistory({
        'infohash': 'same',
        'name': 'replacement',
      }, 'new');
      final after = DateTime.now().millisecondsSinceEpoch;
      final rows = await StorageService.getTorrentSearchHistory();
      expect(rows.map((e) => (e['torrent'] as Map)['infohash']), [
        'same',
        'SAME',
        'b',
        'c',
        'd',
      ]);
      expect(rows.first['torrent'], {
        'infohash': 'same',
        'name': 'replacement',
      });
      expect(rows.first['service'], 'new');
      expect(
        rows.first['clickedAt'],
        allOf(isA<int>(), inInclusiveRange(before, after)),
      );
      expect(rows.skip(1), [_row('SAME'), _row('b'), _row('c'), _row('d')]);
      expect(await StorageService.getTorrentSearchHistoryEnabled(), isFalse);
      expect(backend.writes, ['set:flutter.$_history']);
    },
  );

  for (final hash in [null, '']) {
    test('missing hash $hash still reads history before returning', () async {
      install({_history: 7});
      await expectLater(
        StorageService.addTorrentToHistory({'infohash': hash}, 'x'),
        throwsA(isA<TypeError>()),
      );
      expect(backend.writes, isEmpty);
    });
    test('missing hash $hash does not persist a decoded repair', () async {
      install({_history: '['});
      await StorageService.addTorrentToHistory({'infohash': hash}, 'x');
      expect((await SharedPreferences.getInstance()).getString(_history), '[');
      expect(backend.writes, isEmpty);
    });
  }

  test(
    'wrong incoming hash and malformed nested torrent escape without writes',
    () async {
      await expectLater(
        StorageService.addTorrentToHistory({'infohash': 7}, 'x'),
        throwsA(isA<TypeError>()),
      );
      install({_history: '[{"torrent":7}]'});
      await expectLater(
        StorageService.addTorrentToHistory({'infohash': 'valid'}, 'x'),
        throwsA(isA<TypeError>()),
      );
      expect(backend.writes, isEmpty);
    },
  );

  test('unencodable torrent fails before preference write', () async {
    await expectLater(
      StorageService.addTorrentToHistory({
        'infohash': 'x',
        'bad': Object(),
      }, 'x'),
      throwsA(isA<JsonUnsupportedObjectError>()),
    );
    expect(backend.writes, isEmpty);
  });

  for (final operation in ['add', 'enabled', 'clear']) {
    for (final outcome in ['ok', 'false', 'throw']) {
      test(
        '$operation held transport $outcome preserves cache/durable distinction',
        () async {
          final original = jsonEncode([_row('old')]);
          install({_history: original, _enabled: true});
          final cache = await SharedPreferences.getInstance();
          backend.holdWrite = true;
          backend.outcome = outcome;
          final pending = switch (operation) {
            'add' => StorageService.addTorrentToHistory({
              'infohash': 'new',
            }, 'x'),
            'enabled' => StorageService.setTorrentSearchHistoryEnabled(false),
            _ => StorageService.clearTorrentSearchHistory(),
          };
          final observed = expectLater(
            pending,
            outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
          );
          await backend.entered.future;
          expect((await backend.snapshot())['flutter.$_history'], original);
          expect((await backend.snapshot())['flutter.$_enabled'], isTrue);
          backend.release.complete();
          await observed;
          final durable = await backend.snapshot();
          final key = operation == 'enabled' ? _enabled : _history;
          expect(backend.writes, [
            '${operation == 'clear' ? 'remove' : 'set'}:flutter.$key',
          ]);
          if (operation == 'clear') {
            expect(cache.containsKey(_history), isFalse);
            expect(
              durable['flutter.$_history'],
              outcome == 'ok' ? isNull : original,
            );
          } else if (operation == 'enabled') {
            expect(cache.getBool(_enabled), isFalse);
            expect(durable['flutter.$_enabled'], outcome != 'ok');
            expect(durable['flutter.$_history'], original);
          } else {
            final saved = cache.getString(_history)!;
            expect(
              (jsonDecode(saved) as List).map((e) => e['torrent']['infohash']),
              ['new', 'old'],
            );
            expect(
              durable['flutter.$_history'],
              outcome == 'ok' ? saved : original,
            );
            expect(durable['flutter.$_enabled'], isTrue);
          }
        },
      );
    }
  }

  test(
    'held initial read failure escapes unchanged and performs no writes',
    () async {
      backend.holdRead = true;
      backend.failRead = true;
      final observed = expectLater(
        StorageService.addTorrentToHistory({'infohash': 'x'}, 'x'),
        throwsA(same(backend.failure)),
      );
      await backend.entered.future;
      backend.release.complete();
      await observed;
      expect(backend.writes, isEmpty);
    },
  );

  test(
    'add reacquires history read but writes through original preference cache',
    () async {
      install({
        _history: jsonEncode([_row('first-cache')]),
      });
      final first = await SharedPreferences.getInstance();
      final pending = StorageService.addTorrentToHistory({
        'infohash': 'new',
      }, 'x');
      // Existing SDK test hook: first instance is already awaited by the public
      // call; the later public history read must initialize another cache.
      SharedPreferences.resetStatic();
      backend.holdRead = true;
      await backend.entered.future.timeout(const Duration(seconds: 2));
      expect(backend.reads, 2);
      expect(backend.writes, isEmpty);
      final released = jsonEncode([_row('released-read')]);
      await backend.seed(_history, released);
      backend.release.complete();
      await pending;
      final second = await SharedPreferences.getInstance();
      expect(identical(first, second), isFalse);
      expect(second.getString(_history), released);
      final saved = first.getString(_history)!;
      expect((jsonDecode(saved) as List).map((e) => e['torrent']['infohash']), [
        'new',
        'released-read',
      ]);
      expect((await backend.snapshot())['flutter.$_history'], saved);
    },
  );

  for (final operation in ['add', 'enabled', 'clear']) {
    for (final outcome in ['ok', 'false', 'throw']) {
      for (final switchProfile in [false, true]) {
        test(
          'committed $operation $outcome; profile switch $switchProfile preserves owner and sync',
          () async {
            final a = ProfileScope(
              profileId: 'history-a',
              dataGeneration: 1,
              sessionEpoch: 1,
            );
            final b = ProfileScope(
              profileId: 'history-b',
              dataGeneration: 2,
              sessionEpoch: 2,
            );
            final original = jsonEncode([_row('old')]);
            install({
              for (final scope in [a, b]) ...{
                scope.preferenceKey(_history): original,
                scope.preferenceKey(_enabled): true,
              },
            });
            ProfileRuntime.initializeCommitted(a);
            final signals = <String>[];
            ProfilePreferences.webDavSyncLocalChangeSink = (id, key) {
              signals.add('$id:$key');
            };
            backend.holdWrite = true;
            backend.outcome = outcome;
            final pending = switch (operation) {
              'add' => StorageService.addTorrentToHistory({
                'infohash': 'new',
              }, 'x'),
              'enabled' => StorageService.setTorrentSearchHistoryEnabled(false),
              _ => StorageService.clearTorrentSearchHistory(),
            };
            final observed = expectLater(
              pending,
              outcome == 'throw' ? throwsA(same(backend.failure)) : completes,
            );
            await backend.entered.future.timeout(const Duration(seconds: 2));
            if (switchProfile) ProfileRuntime.publish(b);
            backend.release.complete();
            await observed;
            final durable = await backend.snapshot();
            final key = operation == 'enabled' ? _enabled : _history;
            expect(backend.writes, [
              '${operation == 'clear' ? 'remove' : 'set'}:flutter.${a.preferenceKey(key)}',
            ]);
            expect(
              signals,
              outcome == 'ok' ? ['${a.profileId}:$key'] : isEmpty,
            );
            expect(durable['flutter.${b.preferenceKey(_history)}'], original);
            expect(durable['flutter.${b.preferenceKey(_enabled)}'], isTrue);
            final saved = durable['flutter.${a.preferenceKey(_history)}'];
            if (operation == 'clear' && outcome == 'ok') {
              expect(saved, isNull);
            } else if (operation == 'add' && outcome == 'ok') {
              expect(
                (jsonDecode(saved! as String) as List).map(
                  (e) => e['torrent']['infohash'],
                ),
                ['new', 'old'],
              );
            } else {
              expect(saved, original);
            }
            expect(
              durable['flutter.${a.preferenceKey(_enabled)}'],
              !(operation == 'enabled' && outcome == 'ok'),
            );
            if (switchProfile) {
              expect(await StorageService.getTorrentSearchHistory(), [
                _row('old'),
              ]);
              expect(
                await StorageService.getTorrentSearchHistoryEnabled(),
                isTrue,
              );
            }
          },
        );
      }
    }
  }
}
