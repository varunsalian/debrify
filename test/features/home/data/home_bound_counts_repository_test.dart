import 'dart:async';
import 'package:debrify/features/home/data/home_bound_counts_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'distinct nonempty identities read sequentially and publish only positive immutable counts',
    () async {
      final calls = <String>[];
      final first = Completer<int>();
      final ids = <String?>[null, '', 'tt1', 'native:id', 'tt1', 'zero', ' '];
      final repository = HomeBoundCountsRepository(
        readCount: (id, current) {
          calls.add(id);
          return id == 'tt1'
              ? first.future
              : Future.value(id == 'zero' ? 0 : 2);
        },
      );
      final pending = repository.read(ids, isCurrent: () => true);
      expect(calls, ['tt1']);
      ids.add('late');
      first.complete(3);
      final result = await pending;
      expect(calls, ['tt1', 'native:id', 'zero', ' ']);
      expect(result, {'tt1': 3, 'native:id': 2, ' ': 2});
      expect(() => result!['tt1'] = 7, throwsUnsupportedError);
    },
  );
  test('retirement stops later reads and rejects partial results', () async {
    var active = true;
    final response = Completer<int>();
    final calls = <String>[];
    final repository = HomeBoundCountsRepository(
      readCount: (id, current) {
        calls.add(id);
        return response.future;
      },
    );
    final pending = repository.read(['a', 'b'], isCurrent: () => active);
    active = false;
    response.complete(1);
    expect(await pending, isNull);
    expect(await repository.read(['c'], isCurrent: () => active), isNull);
    expect(calls, ['a']);
  });
  for (final retired in [false, true]) {
    test(
      'service failure propagates only while the request is current: retired=$retired',
      () async {
        var active = true;
        final response = Completer<int>();
        final repository = HomeBoundCountsRepository(
          readCount: (_, current) => response.future,
        );
        final pending = repository.read(['a'], isCurrent: () => active);
        active = !retired;
        response.completeError(StateError('binding read'));
        if (retired) {
          expect(await pending, isNull);
        } else {
          await expectLater(pending, throwsStateError);
        }
      },
    );
  }
}
