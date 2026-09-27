import 'dart:async';
import 'package:debrify/features/home/application/home_trailer_preferences_controller.dart';
import 'package:debrify/features/home/application/home_trailer_preferences_dependencies.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/features/home/models/home_trailer_preferences.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../data/home_trailer_preferences_repository_test.dart'
    show trailerRepository;

HomeCatalogSession session() => HomeCatalogSession(
  owner: ProfileSessionMemory.captureOwner(),
  viewIdentity: Object(),
);
HomeTrailerPreferencesController mount(
  ProviderContainer container,
  HomeCatalogSession key,
) {
  container.listen(homeTrailerPreferencesProvider(key), (_, _) {});
  return container.read(homeTrailerPreferencesProvider(key).notifier);
}

Future<void> load(
  HomeTrailerPreferencesController controller, {
  bool Function()? current,
  void Function(HomeTrailerPreferences)? accepted,
}) => controller.load(
  useHomeAudio: true,
  isCurrent: current ?? () => true,
  onAccepted: accepted ?? (_) {},
);

void main() {
  test(
    'read-free construction, publish-before-effect, repeated disable and failure retention',
    () async {
      var reads = 0;
      var fail = false;
      final container = ProviderContainer.test(
        overrides: [
          homeTrailerPreferencesRepositoryProvider.overrideWithValue(
            trailerRepository(
              enabled: () async {
                reads++;
                if (fail) throw StateError('storage');
                return false;
              },
            ),
          ),
        ],
      );
      final controller = mount(container, session());
      expect(reads, 0);
      expect(controller.current, initialHomeTrailerPreferences);
      var effects = 0;
      for (var i = 0; i < 2; i++) {
        await load(
          controller,
          accepted: (value) {
            expect(controller.current, value);
            expect(value, (enabled: false, volume: 37.0));
            effects++;
          },
        );
      }
      expect(effects, 2);
      fail = true;
      await expectLater(load(controller), throwsStateError);
      expect(controller.current, (enabled: false, volume: 37.0));
    },
  );

  test('late enabled startup cannot undo a newer disabled refresh', () async {
    final first = Completer<bool>();
    var reads = 0;
    final container = ProviderContainer.test(
      overrides: [
        homeTrailerPreferencesRepositoryProvider.overrideWithValue(
          trailerRepository(
            enabled: () => ++reads == 1 ? first.future : Future.value(false),
          ),
        ),
      ],
    );
    final controller = mount(container, session());
    final old = load(
      controller,
      accepted: (_) => fail('stale startup scheduling'),
    );
    await load(controller);
    first.complete(true);
    await old;
    expect(controller.current.enabled, isFalse);
  });

  for (final reason in ['profile', 'view', 'dispose', 'recompute']) {
    test('$reason retires late preferences and effects', () async {
      final response = Completer<bool>();
      final container = ProviderContainer.test(
        overrides: [
          homeTrailerPreferencesRepositoryProvider.overrideWithValue(
            trailerRepository(enabled: () => response.future),
          ),
        ],
      );
      final key = session();
      final controller = mount(container, key);
      var active = true;
      final pending = load(
        controller,
        current: () => active,
        accepted: (_) => fail('retired effect'),
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'view':
          active = false;
        case 'dispose':
          container.dispose();
        case 'recompute':
          container.invalidate(homeTrailerPreferencesProvider(key));
          container.read(homeTrailerPreferencesProvider(key));
      }
      response.complete(true);
      await pending;
      expect(controller.current, initialHomeTrailerPreferences);
    });
  }

  test(
    'owner retirement during state notification suppresses trailer effect',
    () async {
      final container = ProviderContainer.test(
        overrides: [
          homeTrailerPreferencesRepositoryProvider.overrideWithValue(
            trailerRepository(),
          ),
        ],
      );
      final key = session();
      final controller = mount(container, key);
      container.listen(
        homeTrailerPreferencesProvider(key),
        (_, _) => ProfileSessionMemory.clearAll(),
      );
      await load(
        controller,
        accepted: (_) => fail('effect crossed profile handoff'),
      );
    },
  );
}
