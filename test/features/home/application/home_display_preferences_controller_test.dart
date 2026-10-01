import 'dart:async';
import 'package:debrify/features/home/application/home_display_preferences_controller.dart';
import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/features/home/models/home_display_preferences.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../data/home_display_preferences_repository_test.dart'
    show displayRepository;

HomeDisplaySession session() => (
  owner: ProfileSessionMemory.captureOwner(),
  viewIdentity: Object(),
  initial: initialHomeDisplayPreferences,
);
HomeDisplayPreferencesController mount(
  ProviderContainer c,
  HomeDisplaySession key,
) {
  c.listen(homeDisplayPreferencesProvider(key), (_, _) {});
  return c.read(homeDisplayPreferencesProvider(key).notifier);
}

void main() {
  test(
    'read-free bootstrap, changed-only publication and failure retention',
    () async {
      var reads = 0;
      var failed = false;
      final c = ProviderContainer.test(
        overrides: [
          homeDisplayPreferencesRepositoryProvider.overrideWithValue(
            displayRepository(
              focus: () async {
                reads++;
                if (failed) throw StateError('storage');
                return true;
              },
            ),
          ),
        ],
      );
      final controller = mount(c, session());
      expect(controller.current, initialHomeDisplayPreferences);
      expect(reads, 0);
      expect(await controller.load(isCurrent: () => true), isTrue);
      final accepted = controller.current;
      expect(await controller.load(isCurrent: () => true), isFalse);
      failed = true;
      await expectLater(
        controller.load(isCurrent: () => true),
        throwsStateError,
      );
      expect(controller.current, accepted);
      c.invalidate(homeDisplayPreferencesRepositoryProvider);
      c.read(homeDisplayPreferencesProvider(controller.session));
      expect(controller.current, accepted);
    },
  );

  test('late startup cannot overwrite a newer settings refresh', () async {
    final first = Completer<bool>();
    var reads = 0;
    final c = ProviderContainer.test(
      overrides: [
        homeDisplayPreferencesRepositoryProvider.overrideWithValue(
          displayRepository(
            focus: () => ++reads == 1 ? first.future : Future.value(true),
          ),
        ),
      ],
    );
    final controller = mount(c, session());
    final old = controller.load(isCurrent: () => true);
    expect(await controller.load(isCurrent: () => true), isTrue);
    first.complete(false);
    expect(await old, isFalse);
    expect(controller.current.spotlightFocusDetails, isTrue);
  });

  for (final reason in ['profile', 'view', 'dispose', 'recompute']) {
    test('$reason retires pending settings before publication', () async {
      final pending = Completer<bool>();
      final c = ProviderContainer.test(
        overrides: [
          homeDisplayPreferencesRepositoryProvider.overrideWithValue(
            displayRepository(focus: () => pending.future),
          ),
        ],
      );
      final key = session();
      final controller = mount(c, key);
      var active = true;
      final load = controller.load(isCurrent: () => active);
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'view':
          active = false;
        case 'dispose':
          c.dispose();
        case 'recompute':
          c.invalidate(homeDisplayPreferencesProvider(key));
          c.read(homeDisplayPreferencesProvider(key));
      }
      pending.complete(true);
      expect(await load, isFalse);
      expect(controller.current, initialHomeDisplayPreferences);
    });
  }

  test('sibling views retain independent display preferences', () async {
    final c = ProviderContainer.test(
      overrides: [
        homeDisplayPreferencesRepositoryProvider.overrideWithValue(
          displayRepository(),
        ),
      ],
    );
    final one = mount(c, session());
    final two = mount(c, session());
    await one.load(isCurrent: () => true);
    expect(one.current.spotlightFocusDetails, isTrue);
    expect(two.current, initialHomeDisplayPreferences);
  });
}
