import 'dart:async';
import 'package:debrify/features/discover/application/discover_layout_controller.dart';
import 'package:debrify/features/discover/application/discover_providers.dart';
import 'package:debrify/features/discover/data/discover_layout_preferences.dart';
import 'package:debrify/features/discover/models/discover_layout_session.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late DiscoverLayoutSession key;
  late DiscoverLayoutController controller;
  final reads = <Completer<String>>[];
  final guards = <bool Function()>[];
  final remembered = <String>[];
  final changed = <String>[];
  var mounted = true;
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    reads.clear();
    guards.clear();
    remembered.clear();
    changed.clear();
    mounted = true;
    key = (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
    container = ProviderContainer.test(
      overrides: [
        discoverLayoutPreferencesProvider.overrideWith(
          (ref, session) => DiscoverLayoutPreferences(
            readCached: () => 'grid',
            readSaved: (current) {
              guards.add(current);
              final response = Completer<String>();
              reads.add(response);
              return response.future;
            },
            remember: remembered.add,
          ),
        ),
      ],
    );
    container.listen(discoverLayoutProvider(key), (_, _) {});
    controller = container.read(discoverLayoutProvider(key).notifier);
  });
  tearDown(ProfileRuntime.debugReset);
  Future<void> load() => controller.load(
    isCurrent: () => mounted,
    onChanged: () => changed.add(controller.current),
  );

  test(
    'warm construction is read-free and equal reads remember without repaint',
    () async {
      expect(controller.current, 'grid');
      expect(reads, isEmpty);
      final equal = load();
      reads.last.complete('grid');
      await equal;
      expect(remembered, ['grid']);
      expect(changed, isEmpty);
      final next = load();
      reads.last.complete('stage');
      await next;
      expect(remembered, ['grid', 'stage']);
      expect(changed, ['stage']);
    },
  );

  test(
    'newest read wins visible state and both cache/publication guards',
    () async {
      final old = load();
      final newer = load();
      expect(guards.first(), isFalse);
      expect(guards.last(), isTrue);
      reads.last.complete('stage');
      await newer;
      reads.first.complete('grid');
      await old;
      expect(controller.current, 'stage');
      expect(remembered, ['stage']);
      expect(changed, ['stage']);
    },
  );

  test(
    'unmounted views neither start reads nor publish pending reads',
    () async {
      mounted = false;
      await load();
      expect(reads, isEmpty);
      mounted = true;
      final pending = load();
      mounted = false;
      expect(guards.single(), isFalse);
      reads.single.complete('stage');
      await pending;
      expect(remembered, isEmpty);
      expect(changed, isEmpty);
    },
  );

  test(
    'active failures propagate once; superseded failures are retired',
    () async {
      final active = load();
      final assertion = expectLater(active, throwsStateError);
      reads.last.completeError(StateError('read unavailable'));
      await assertion;
      expect(controller.current, 'grid');
      expect(reads, hasLength(1));
      final old = load();
      final newer = load();
      reads.last.complete('stage');
      await newer;
      reads[1].completeError(StateError('old error'));
      await old;
      expect(remembered, ['stage']);
      expect(changed, ['stage']);
    },
  );

  for (final retire in ['dispose', 'recompute', 'profile', 'handoff']) {
    test(
      '$retire prevents pending cache writes and view transitions',
      () async {
        final pending = load();
        switch (retire) {
          case 'dispose':
            container.dispose();
          case 'recompute':
            container.invalidate(discoverLayoutProvider(key));
            container.read(discoverLayoutProvider(key));
          case 'profile':
            ProfileRuntime.promoteLegacyToCommitted(
              ProfileScope(
                profileId: 'next',
                dataGeneration: 1,
                sessionEpoch: 1,
              ),
            );
          case 'handoff':
            ProfileSessionMemory.clearAll();
        }
        expect(guards.single(), isFalse);
        reads.single.complete('stage');
        await pending;
        expect(remembered, isEmpty);
        expect(changed, isEmpty);
      },
    );
  }

  test(
    'recomputation retains accepted layout without starting another read',
    () async {
      final pending = load();
      reads.last.complete('stage');
      await pending;
      container.invalidate(discoverLayoutProvider(key));
      expect(container.read(discoverLayoutProvider(key)), 'stage');
      expect(reads, hasLength(1));
      expect(changed, ['stage']);
    },
  );
}
