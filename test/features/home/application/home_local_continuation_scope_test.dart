import 'package:flutter_test/flutter_test.dart';
import '../fixtures/home_continuation_fixture.dart';

void main() {
  test(
    'explicit child scopes and sibling views retain independent continuation state',
    () async {
      final session = continuationSession();
      final calls = <String>[];
      final parent = ProviderContainer.test(
        overrides: [
          homeLocalContinuationRepositoryProvider.overrideWithValue(
            continuationRepository(
              readItems: () async {
                calls.add('parent');
                return history('parent');
              },
            ),
          ),
        ],
      );
      final root = mountContinuation(parent, session);
      await loadContinuation(root);
      final sibling = mountContinuation(parent, continuationSession());
      expect(sibling.current.data.items, isEmpty);
      for (final label in ['one', 'two']) {
        final child = ProviderContainer.test(
          parent: parent,
          overrides: [
            homeLocalContinuationRepositoryProvider.overrideWithValue(
              continuationRepository(
                readItems: () async {
                  calls.add(label);
                  return history(label);
                },
              ),
            ),
            homeLocalContinuationProvider(
              session,
            ).overrideWith(() => HomeLocalContinuationController(session)),
          ],
        );
        final controller = mountContinuation(child, session);
        await loadContinuation(controller);
        expect(controller.current.movies.single.id, label);
        expect(root.current.movies.single.id, 'parent');
        expect(sibling.current.data.items, isEmpty);
        child.dispose();
      }
      await loadContinuation(sibling);
      expect(sibling.current.movies.single.id, 'parent');
      expect(calls, ['parent', 'one', 'two', 'parent']);
    },
  );

  test(
    'retired profile cannot start reads even if the view predicate accepts',
    () async {
      var reads = 0;
      final container = ProviderContainer.test(
        overrides: [
          homeLocalContinuationRepositoryProvider.overrideWithValue(
            continuationRepository(
              readSource: () async {
                reads++;
                return WatchProgressSource.local;
              },
              readItems: () async => history('incoming'),
            ),
          ),
        ],
      );
      final outgoing = mountContinuation(container, continuationSession());
      ProfileSessionMemory.clearAll();
      await loadContinuation(outgoing);
      expect(reads, 0);
      final incoming = mountContinuation(container, continuationSession());
      await loadContinuation(incoming);
      expect(reads, 1);
      expect(outgoing.current.data.items, isEmpty);
      expect(incoming.current.movies.single.id, 'incoming');
    },
  );
}
