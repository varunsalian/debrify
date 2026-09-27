import 'dart:async';

import 'package:debrify/features/home/data/home_collections_repository.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'each read is fresh and returns a read-only container with original identities',
    () async {
      const first = HomeCollection(id: 'a', title: 'First');
      const second = HomeCollection(id: 'b', title: 'Second');
      var source = [first];
      var reads = 0;
      final repository = HomeCollectionsRepository(
        read: () async {
          reads++;
          return source;
        },
        signature: (_) async => 'unused',
        onReadFailure: () => fail('unexpected read failure'),
      );
      final result = await repository.read();
      source.clear();
      expect(result.single, same(first));
      expect(() => result.clear(), throwsUnsupportedError);
      source = [second];
      expect((await repository.read()).single, same(second));
      expect(result.single, same(first));
      expect(reads, 2);
    },
  );

  test(
    'failed reads report once and fall back to empty without caching failure',
    () async {
      var reports = 0;
      var reads = 0;
      final repository = HomeCollectionsRepository(
        read: () async {
          if (reads++ == 0) throw StateError('fixture');
          return [const HomeCollection(id: 'recovered', title: 'Recovered')];
        },
        signature: (_) async => 'unused',
        onReadFailure: () => reports++,
      );
      expect(await repository.read(), isEmpty);
      expect((await repository.read()).single.id, 'recovered');
      expect(reports, 1);
      expect(reads, 2);
    },
  );

  test(
    'signature keeps the worker future and propagates errors separately from reads',
    () async {
      final response = Completer<String>();
      final collections = [const HomeCollection(id: 'a', title: 'A')];
      List<HomeCollection>? received;
      var reports = 0;
      final repository = HomeCollectionsRepository(
        read: () async => collections,
        signature: (value) {
          received = value;
          return response.future;
        },
        onReadFailure: () => reports++,
      );
      final snapshot = await repository.read();
      final signature = repository.signature(snapshot);
      expect(received, same(snapshot));
      expect(signature, same(response.future));
      final failed = expectLater(signature, throwsStateError);
      response.completeError(StateError('worker fixture'));
      await failed;
      expect(reports, 0);
    },
  );
}
