import 'dart:async';
import 'package:debrify/features/discover/application/metadata_feature_controller.dart';
import 'package:debrify/features/discover/application/discover_providers.dart';
import 'package:debrify/features/discover/models/metadata_feature_policy.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late MetadataFeatureSession key;
  late MetadataFeatureController controller;
  final reads = <Completer<MetadataPreferences>>[];
  var unexpectedEffects = 0;
  tearDown(() => expect(unexpectedEffects, 0));
  setUp(() {
    reads.clear();
    unexpectedEffects = 0;
    key = (owner: ProfileSessionMemory.captureOwner(), viewIdentity: Object());
    container = ProviderContainer.test(
      overrides: [
        metadataFeatureReaderProvider.overrideWith(
          (ref, session) => () {
            final response = Completer<MetadataPreferences>();
            reads.add(response);
            return response.future;
          },
        ),
      ],
    );
    container.listen(metadataFeaturePolicyProvider(key), (_, _) {});
    controller = container.read(metadataFeaturePolicyProvider(key).notifier);
  });
  Future<void> load({
    bool Function()? current,
    void Function(MetadataPreferences)? accepted,
  }) => controller.load(
    isCurrent: current ?? () => true,
    onAccepted: accepted ?? (_) {},
  );
  test(
    'read-free construction; acceptance makes policy ready before effects',
    () async {
      expect(reads, isEmpty);
      expect(controller.current, (preferences: null, ready: false));
      final policy = MetadataPreferences(language: 'hi-IN');
      MetadataPreferences? effectValue;
      MetadataFeaturePolicy? atEffect;
      final pending = load(
        accepted: (value) {
          effectValue = value;
          atEffect = controller.current;
        },
      );
      reads.single.complete(policy);
      await pending;
      expect(controller.current.preferences!.language, 'hi-IN');
      expect(effectValue, same(policy));
      expect(atEffect, (preferences: policy, ready: true));
    },
  );
  test(
    'invalidation retains policy but blocks suggestions; failed reload stays unready',
    () async {
      final policy = MetadataPreferences();
      final initial = load();
      reads.single.complete(policy);
      await initial;
      controller.invalidate();
      expect(controller.current, (preferences: policy, ready: false));
      final failed = load(accepted: (_) => unexpectedEffects++);
      reads.last.completeError(StateError('profile unavailable'));
      await failed;
      expect(controller.current, (preferences: policy, ready: false));
      expect(reads.length, 2);
    },
  );
  test(
    'ordinary failed refresh retains the ready policy and does not retry',
    () async {
      final policy = MetadataPreferences();
      final initial = load();
      reads.single.complete(policy);
      await initial;
      final failed = load(accepted: (_) => unexpectedEffects++);
      reads.last.completeError(StateError('unavailable'));
      await failed;
      expect(controller.current, (preferences: policy, ready: true));
      expect(reads.length, 2);
    },
  );
  test('newer disabled settings defeat delayed enabled settings', () async {
    final old = load(accepted: (_) => unexpectedEffects++);
    controller.invalidate();
    final newer = load();
    final disabled = MetadataPreferences(features: {});
    reads.last.complete(disabled);
    await newer;
    reads.first.complete(MetadataPreferences());
    await old;
    expect(controller.current.preferences, same(disabled));
  });
  for (final reason in [
    'profile',
    'view',
    'dispose',
    'recompute',
    'invalidate',
  ]) {
    test('$reason retires a pending read', () async {
      var current = true;
      final pending = load(
        current: () => current,
        accepted: (_) => unexpectedEffects++,
      );
      switch (reason) {
        case 'profile':
          ProfileSessionMemory.clearAll();
        case 'view':
          current = false;
        case 'dispose':
          container.dispose();
        case 'recompute':
          container.invalidate(metadataFeaturePolicyProvider(key));
          container.read(metadataFeaturePolicyProvider(key));
        case 'invalidate':
          controller.invalidate();
      }
      reads.single.complete(MetadataPreferences());
      await pending;
      expect(controller.current, (preferences: null, ready: false));
    });
  }
  test(
    'recomputation retains accepted policy without reads or effects',
    () async {
      final policy = MetadataPreferences();
      final initial = load();
      reads.single.complete(policy);
      await initial;
      container.invalidate(metadataFeaturePolicyProvider(key));
      expect(container.read(metadataFeaturePolicyProvider(key)), (
        preferences: policy,
        ready: true,
      ));
      expect(reads.length, 1);
    },
  );
  test(
    'owner retirement during publication prevents suggestion and navigation effects',
    () async {
      var effects = 0;
      container.listen(
        metadataFeaturePolicyProvider(key),
        (_, _) => ProfileSessionMemory.clearAll(),
      );
      final pending = load(accepted: (_) => effects++);
      reads.single.complete(MetadataPreferences());
      await pending;
      expect(effects, 0);
    },
  );
  test(
    'separate views do not supersede each other; rejected work does not read',
    () async {
      final otherKey = (owner: key.owner, viewIdentity: Object());
      container.listen(metadataFeaturePolicyProvider(otherKey), (_, _) {});
      final other = container.read(
        metadataFeaturePolicyProvider(otherKey).notifier,
      );
      final first = load();
      final second = other.load(isCurrent: () => true, onAccepted: (_) {});
      reads[1].complete(MetadataPreferences(language: 'fr-FR'));
      await second;
      reads[0].complete(MetadataPreferences(language: 'hi-IN'));
      await first;
      expect(controller.current.preferences!.language, 'hi-IN');
      expect(other.current.preferences!.language, 'fr-FR');
      await load(current: () => false);
      ProfileSessionMemory.clearAll();
      await load();
      expect(reads.length, 2);
    },
  );
}
