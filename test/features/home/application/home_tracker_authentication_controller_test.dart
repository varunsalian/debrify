import 'dart:async';
import 'package:debrify/features/home/application/home_tracker_authentication_controller.dart';
import 'package:debrify/features/home/application/home_tracker_authentication_dependencies.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/features/home/models/home_tracker_authentication.dart';

void main() {
  late ProviderContainer container;
  late HomeTrackerAuthSession key;
  late HomeTrackerAuthenticationController controller;
  void mount(Future<bool> Function() read) {
    container = ProviderContainer.test(
      overrides: [
        homeTrackerAuthReaderProvider.overrideWith((ref, session) => read),
      ],
    );
    key = (
      view: HomeCatalogSession(
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      ),
      tracker: HomeTracker.mdblist,
    );
    container.listen(homeTrackerAuthenticationProvider(key), (_, _) {});
    controller = container.read(
      homeTrackerAuthenticationProvider(key).notifier,
    );
  }

  Future<void> load({bool Function()? current, void Function()? changed}) =>
      controller.load(
        isCurrent: current ?? () => true,
        onChanged: (_) => changed?.call(),
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
  test('newer authentication refresh wins over delayed startup', () async {
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
    test('$reason retires pending authentication', () async {
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
          container.invalidate(homeTrackerAuthenticationProvider(key));
          container.read(homeTrackerAuthenticationProvider(key));
      }
      response.complete(true);
      await pending;
      expect(controller.current, isFalse);
    });
  }
  test('owner retirement during publication prevents repaint', () async {
    mount(() async => true);
    container.listen(
      homeTrackerAuthenticationProvider(key),
      (_, _) => ProfileSessionMemory.clearAll(),
    );
    await load(changed: () => fail('retired repaint'));
  });
  test(
    'disconnect clears outgoing state before publication and then changes mode',
    () async {
      var authenticated = true;
      mount(() async => authenticated);
      await load();
      authenticated = false;
      final events = <String>[];
      await controller.load(
        isCurrent: () => true,
        beforeChange: (value) {
          expect(value, isFalse);
          expect(controller.current, isTrue);
          events.add('clear lists');
        },
        onChanged: (value) {
          expect(controller.current, isFalse);
          events.add('catalog');
        },
      );
      expect(events, ['clear lists', 'catalog']);
    },
  );
  test(
    'retirement while clearing outgoing state prevents acceptance',
    () async {
      mount(() async => true);
      await controller.load(
        isCurrent: () => true,
        beforeChange: (_) => ProfileSessionMemory.clearAll(),
        onChanged: (_) => fail('retired effect'),
      );
      expect(controller.current, isFalse);
    },
  );
  test('rejected action does not read authentication', () async {
    var reads = 0;
    mount(() async {
      reads++;
      return true;
    });
    await load(current: () => false);
    ProfileSessionMemory.clearAll();
    await load();
    expect(reads, 0);
  });
  test('trackers own independent requests within the same view', () async {
    final responses = <Completer<bool>>[];
    mount(() {
      final response = Completer<bool>();
      responses.add(response);
      return response.future;
    });
    final otherKey = (view: key.view, tracker: HomeTracker.trakt);
    container.listen(homeTrackerAuthenticationProvider(otherKey), (_, _) {});
    final other = container.read(
      homeTrackerAuthenticationProvider(otherKey).notifier,
    );
    final first = load();
    final second = other.load(isCurrent: () => true, onChanged: (_) {});
    responses[1].complete(true);
    await second;
    responses[0].complete(true);
    await first;
    expect(controller.current, isTrue);
    expect(other.current, isTrue);
  });
}
