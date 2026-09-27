import 'package:debrify/features/discover/application/discover_card_settings_controller.dart';
import 'package:debrify/features/discover/application/discover_card_settings_dependencies.dart';
import 'package:debrify/features/discover/models/discover_card_settings.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const hidden = (showTypeTags: false, showRatings: false, showTitles: false);

void main() {
  late ProviderContainer container;
  late DiscoverCardSettingsSession key;
  late DiscoverCardSettingsController controller;
  var values = defaultDiscoverCardSettings;
  var reads = 0;
  void Function()? duringRead;
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    values = defaultDiscoverCardSettings;
    reads = 0;
    duringRead = null;
    key = (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
    container = ProviderContainer.test(
      overrides: [
        discoverCardSettingsReaderProvider.overrideWith(
          (ref, session) => () {
            reads++;
            duringRead?.call();
            return values;
          },
        ),
      ],
    );
    container.listen(discoverCardSettingsProvider(key), (_, _) {});
    controller = container.read(discoverCardSettingsProvider(key).notifier);
  });
  tearDown(ProfileRuntime.debugReset);

  test('warm values are immediate; only changed refreshes publish', () {
    expect(reads, 1);
    expect(controller.current, defaultDiscoverCardSettings);
    final emitted = <DiscoverCardSettings>[];
    container.listen(
      discoverCardSettingsProvider(key),
      (_, next) => emitted.add(next),
    );
    expect(controller.refresh(isCurrent: () => true), isFalse);
    values = hidden;
    expect(controller.refresh(isCurrent: () => true), isTrue);
    expect(controller.current, hidden);
    expect(emitted, [hidden]);
    expect(controller.refresh(isCurrent: () => true), isFalse);
    expect(emitted, [hidden]);
  });

  test(
    'Home snapshot reads fresh flags without changing the displayed snapshot',
    () {
      values = hidden;
      expect(controller.readSnapshot(isCurrent: () => true), hidden);
      expect(controller.current, defaultDiscoverCardSettings);
      expect(reads, 2);
      expect(
        controller.readSnapshot(isCurrent: () => false),
        defaultDiscoverCardSettings,
      );
      expect(reads, 2);
    },
  );

  for (final retire in ['dispose', 'profile', 'handoff']) {
    test('$retire stops reads and keeps the last accepted snapshot', () {
      values = hidden;
      controller.refresh(isCurrent: () => true);
      switch (retire) {
        case 'dispose':
          container.dispose();
        case 'profile':
          ProfileRuntime.promoteLegacyToCommitted(
            ProfileScope(profileId: 'next', dataGeneration: 1, sessionEpoch: 1),
          );
        case 'handoff':
          ProfileSessionMemory.clearAll();
      }
      values = defaultDiscoverCardSettings;
      expect(controller.refresh(isCurrent: () => true), isFalse);
      expect(controller.readSnapshot(isCurrent: () => true), hidden);
      expect(reads, 2);
    });
  }

  test(
    'retirement during a synchronous injected read prevents publication',
    () {
      values = hidden;
      duringRead = ProfileSessionMemory.clearAll;
      expect(controller.refresh(isCurrent: () => true), isFalse);
      expect(controller.current, defaultDiscoverCardSettings);
    },
  );

  test(
    'recomputation retains state and refresh uses the newly bound reader',
    () {
      values = hidden;
      container.invalidate(discoverCardSettingsProvider(key));
      expect(
        container.read(discoverCardSettingsProvider(key)),
        defaultDiscoverCardSettings,
      );
      expect(reads, 1);
      expect(controller.refresh(isCurrent: () => true), isTrue);
      expect(controller.current, hidden);
    },
  );

  test(
    'read errors propagate without replacing accepted state or retrying',
    () {
      duringRead = () => throw StateError('unavailable');
      expect(() => controller.refresh(isCurrent: () => true), throwsStateError);
      expect(controller.current, defaultDiscoverCardSettings);
      expect(reads, 2);
    },
  );

  test('independent view snapshots do not refresh each other', () {
    final secondKey = (owner: key.owner, viewIdentity: Object());
    container.listen(discoverCardSettingsProvider(secondKey), (_, _) {});
    final second = container.read(
      discoverCardSettingsProvider(secondKey).notifier,
    );
    values = hidden;
    controller.refresh(isCurrent: () => true);
    expect(second.current, defaultDiscoverCardSettings);
    expect(second.readSnapshot(isCurrent: () => true), hidden);
    expect(second.current, defaultDiscoverCardSettings);
  });
}
