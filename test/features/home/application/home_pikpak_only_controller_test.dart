import 'dart:async';
import 'package:debrify/features/home/application/home_pikpak_only_controller.dart';
import 'package:debrify/features/home/application/home_pikpak_only_dependencies.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../data/home_pikpak_only_repository_test.dart' show pikpakRepository;

void main() {
  late ProviderContainer container;
  late HomeCatalogSession key;
  late HomePikpakOnlyController controller;
  void mount(Future<bool> Function() read) {
    container = ProviderContainer.test(
      overrides: [
        homePikpakOnlyRepositoryProvider.overrideWith(
          (ref, session) => pikpakRepository(read),
        ),
      ],
    );
    key = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(homePikpakOnlyProvider(key), (_, _) {});
    controller = container.read(homePikpakOnlyProvider(key).notifier);
  }

  Future<void> load({bool Function()? current, void Function()? changed}) =>
      controller.load(
        isCurrent: current ?? () => true,
        onChanged: changed ?? () {},
      );
  test(
    'read-free initial state; only changes repaint; errors retain the accepted value',
    () async {
      var reads = 0;
      var value = true;
      var error = false;
      mount(() async {
        reads++;
        if (error) throw StateError('read');
        return value;
      });
      expect(reads, 0);
      expect(controller.current, isFalse);
      var effects = 0;
      await load(
        changed: () {
          effects++;
          expect(controller.current, isTrue);
        },
      );
      await load(changed: () => fail('unchanged repaint'));
      error = true;
      await expectLater(load(), throwsStateError);
      expect(controller.current, isTrue);
      error = false;
      value = false;
      await load(changed: () => effects++);
      expect(controller.current, isFalse);
      expect(effects, 2);
      expect(reads, 4);
    },
  );
  test('newer availability refresh wins over delayed startup', () async {
    final response = Completer<bool>();
    var reads = 0;
    mount(() => ++reads == 1 ? response.future : Future.value(false));
    final pending = load(changed: () => fail('stale repaint'));
    await load();
    response.complete(true);
    await pending;
    expect(controller.current, isFalse);
  });
  for (final reason in ['profile', 'view', 'dispose', 'recompute']) {
    test('$reason retires pending availability', () async {
      final response = Completer<bool>();
      mount(() => response.future);
      var active = true;
      final pending = load(
        current: () => active,
        changed: () => fail('retired repaint'),
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'view':
          active = false;
        case 'dispose':
          container.dispose();
        case 'recompute':
          container.invalidate(homePikpakOnlyProvider(key));
          container.read(homePikpakOnlyProvider(key));
      }
      response.complete(true);
      await pending;
      expect(controller.current, isFalse);
    });
  }
  test('owner retirement during publication prevents repaint', () async {
    mount(() async => true);
    container.listen(
      homePikpakOnlyProvider(key),
      (_, _) => ProfileSessionMemory.clearAll(),
    );
    await load(changed: () => fail('retired repaint'));
  });
}
