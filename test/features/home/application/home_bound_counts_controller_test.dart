import 'dart:async';
import 'package:debrify/features/home/application/home_bound_counts_controller.dart';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/data/home_bound_counts_repository.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late HomeCatalogSession key;
  late HomeBoundCountsController controller;
  void mount(Future<int> Function(String, bool Function()) read) {
    container = ProviderContainer.test(
      overrides: [
        homeBoundCountsRepositoryProvider.overrideWith(
          (ref, session) => HomeBoundCountsRepository(readCount: read),
        ),
      ],
    );
    key = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(homeBoundCountsProvider(key), (_, _) {});
    controller = container.read(homeBoundCountsProvider(key).notifier);
  }

  Future<void> load({
    List<String?> ids = const ['a'],
    bool Function()? current,
    void Function()? accepted,
  }) => controller.load(
    ids: ids,
    isCurrent: current ?? () => true,
    onAccepted: accepted ?? () {},
  );

  test(
    'read-free startup; full publication before repaint; errors retain old counts; empty clears',
    () async {
      var reads = 0;
      var error = false;
      mount((_, current) async {
        reads++;
        if (error) throw StateError('read');
        return 2;
      });
      expect(reads, 0);
      expect(controller.current, isEmpty);
      await load(accepted: () => expect(controller.current, {'a': 2}));
      error = true;
      await expectLater(load(), throwsStateError);
      expect(controller.current, {'a': 2});
      await load(ids: [], accepted: () => expect(controller.current, isEmpty));
      expect(reads, 2);
    },
  );
  test(
    'a newer title snapshot wins; older completion cannot publish or continue scanning',
    () async {
      final response = Completer<int>();
      final calls = <String>[];
      mount((id, current) {
        calls.add(id);
        return id == 'old' ? response.future : Future.value(3);
      });
      final pending = load(
        ids: ['old', 'never'],
        accepted: () => fail('stale repaint'),
      );
      await load(ids: ['new']);
      response.complete(8);
      await pending;
      expect(controller.current, {'new': 3});
      expect(calls, ['old', 'new']);
    },
  );
  for (final reason in ['profile', 'view', 'dispose', 'recompute']) {
    test('$reason retires the service guard and rejects late counts', () async {
      final response = Completer<int>();
      bool Function()? guard;
      mount((_, current) {
        guard = current;
        return response.future;
      });
      var active = true;
      final pending = load(
        current: () => active,
        accepted: () => fail('retired repaint'),
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'view':
          active = false;
        case 'dispose':
          container.dispose();
        case 'recompute':
          container.invalidate(homeBoundCountsProvider(key));
          container.read(homeBoundCountsProvider(key));
      }
      expect(guard!(), isFalse);
      response.complete(3);
      await pending;
      expect(controller.current, isEmpty);
    });
  }
  test('profile change during publication suppresses repaint', () async {
    mount((_, current) async => 1);
    container.listen(
      homeBoundCountsProvider(key),
      (_, _) => ProfileSessionMemory.clearAll(),
    );
    await load(accepted: () => fail('retired repaint'));
  });
}
