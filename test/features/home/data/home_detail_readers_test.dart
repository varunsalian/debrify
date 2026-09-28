import 'dart:async';

import 'package:debrify/features/home/data/home_detail_readers.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_test/flutter_test.dart';

const title = StremioMeta(id: 'tt123', type: 'series', name: 'Title');
const trakt = TraktTitleStatus(inWatchlist: true, rating: 8);
const simkl = SimklTitleStatus(currentStatus: 'watching', rating: 7);
const mdblist = MdblistTitleStatus(id: 123, inProgress: true);

class Fixture {
  bool owner = true, route = true;
  final release = Completer<void>();
  final calls = <String>[];
  bool Function()? current;
  Object? failure;

  Future<T> read<T>(
    String name,
    String id,
    String type,
    bool Function() guard,
    T value,
  ) async {
    calls.add('$name:$id:$type');
    current = guard;
    await release.future;
    if (failure != null) throw failure!;
    return value;
  }

  late final readers = HomeDetailReaders(
    isOwnerCurrent: () => owner,
    trakt: (id, type, guard) => read('trakt', id, type, guard, trakt),
    simkl: (id, type, guard) => read('simkl', id, type, guard, simkl),
    mdblist: (id, type, guard) => read('mdblist', id, type, guard, mdblist),
    recommendations: (id, type, guard) =>
        read('recommendations', id, type, guard, [title]),
    metadata: (id, type, guard) => read('metadata', id, type, guard, title),
  );

  Future<Object?> load(String name) => switch (name) {
    'trakt' => readers.trakt('tt123', 'series', isCurrent: () => route),
    'simkl' => readers.simkl('tt123', 'series', isCurrent: () => route),
    'mdblist' => readers.mdblist('tt123', 'series', isCurrent: () => route),
    'recommendations' => readers.recommendations(
      'tt123',
      'series',
      isCurrent: () => route,
    ),
    _ => readers.metadata('tt123', 'series', isCurrent: () => route),
  };
}

void main() {
  final expected = <String, Object>{
    'trakt': trakt,
    'simkl': simkl,
    'mdblist': mdblist,
    'recommendations': [title],
    'metadata': title,
  };
  for (final entry in expected.entries) {
    test('${entry.key}: lazy read preserves identity and value', () async {
      final f = Fixture();
      f.readers;
      expect(f.calls, isEmpty);
      final result = f.load(entry.key);
      expect(f.calls, ['${entry.key}:tt123:series']);
      expect(f.current!(), isTrue);
      f.release.complete();
      expect(await result, entry.value);
    });
    for (final retireOwner in [false, true]) {
      test(
        '${entry.key}: rejects retired ${retireOwner ? 'profile' : 'route'}',
        () async {
          final f = Fixture();
          final result = f.load(entry.key);
          if (retireOwner) {
            f.owner = false;
          } else {
            f.route = false;
          }
          expect(f.current!(), isFalse);
          f.release.complete();
          final empty = entry.key == 'recommendations' ? isEmpty : isNull;
          expect(await result, empty);
          expect(await f.load(entry.key), empty);
          expect(f.calls, hasLength(1));
        },
      );
    }
    test('${entry.key}: preserves service failure without retry', () async {
      final f = Fixture()..failure = StateError('failure');
      final result = f.load(entry.key);
      final check = expectLater(result, throwsA(same(f.failure)));
      f.release.complete();
      await check;
      expect(f.calls, hasLength(1));
    });
  }
}
