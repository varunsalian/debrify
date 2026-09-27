import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/features/home/application/home_return_dependencies.dart';
import 'package:debrify/features/home/data/home_return_repository.dart';
import 'package:debrify/features/home/models/home_return_snapshot.dart';
import 'package:debrify/screens/search_screen.dart';
import 'package:debrify/widgets/skeleton_poster.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../home_progressive_pagination_test.dart' show HomeFixture, page;

class ObservedReturnRepository extends HomeReturnRepository {
  ObservedReturnRepository({
    required super.owner,
    required this.onTake,
    required this.onStore,
  });
  final VoidCallback onTake;
  final VoidCallback onStore;
  @override
  HomeReturnSnapshot? take({DateTime? now}) {
    onTake();
    return super.take(now: now);
  }

  @override
  void store(HomeReturnSnapshot snapshot, {required int revision}) {
    onStore();
    super.store(snapshot, revision: revision);
  }
}

void main() {
  testWidgets(
    'repeated Home visits use the injected cache on the first frame without refetching',
    (tester) async {
      var takes = 0;
      var stores = 0;
      final shown = ValueNotifier(true);
      addTearDown(shown.dispose);
      final home = HomeFixture(tester);
      await home.mount(
        wrap: (child) => ProviderScope(
          overrides: [
            homeReturnRepositoryProvider.overrideWith(
              (ref, owner) => ObservedReturnRepository(
                owner: owner,
                onTake: () => takes++,
                onStore: () => stores++,
              ),
            ),
          ],
          child: ValueListenableBuilder<bool>(
            valueListenable: shown,
            child: child,
            builder: (_, value, screen) =>
                value ? screen! : const Text('Settings'),
          ),
        ),
      );
      await home.drive(() => home.slow.complete(page('Slow')));
      await home.settle();
      final requests = List.of(home.requests);
      final registered = ProfileSessionMemory.debugRegisteredStoreCount;
      for (var visit = 0; visit < 3; visit++) {
        final outgoing = tester.state(find.byType(SearchScreen));
        shown.value = false;
        await home.pump(Duration.zero);
        expect(outgoing.mounted, isFalse);
        shown.value = true;
        await home.pump(Duration.zero);
        expect(find.byType(BrandLoadingStage), findsNothing);
        expect(find.text('Fast 0'), findsWidgets);
        await home.settle();
        expect(home.requests, requests);
        expect(ProfileSessionMemory.debugRegisteredStoreCount, registered);
      }
      expect(takes, 4);
      expect(stores, 3);
      await home.dispose();
      expect(stores, 4);
      expect(tester.takeException(), isNull);
    },
  );
}
