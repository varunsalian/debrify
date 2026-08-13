import 'dart:convert';
import 'dart:math';

import 'profile_data_generation.dart';
import 'profile_lifecycle.dart';
import 'profile_registry.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';

/// Resets only the active profile's mutable app state.
///
/// Identity, role, policy, PIN, resources/grants, device jobs, and public media
/// artifacts are deliberately outside the replaced data generation.
class ProfileResetService {
  final ProfileRegistry registry;
  final List<ProfileLifecycleParticipant> lifecycleParticipants;

  const ProfileResetService({
    required this.registry,
    this.lifecycleParticipants = const <ProfileLifecycleParticipant>[],
  });

  Future<void> resetActiveProfile() async {
    final current = ProfileRuntime.capture();
    final operationId = _newId();
    var published = false;
    ProfileScope? candidate;

    for (final participant in lifecycleParticipants) {
      await participant.prepareDeactivate(current);
    }
    try {
      final staged = await ProfileDataGenerationManager(registry).stage(
        operationId: operationId,
        profileId: current.profileId,
        preferenceOverlay: const <String, Object?>{
          'initial_setup_complete_v1': false,
        },
        replacePreferences: true,
        copyDurableAreas: false,
      );
      candidate = ProfileScope(
        profileId: current.profileId,
        dataGeneration: staged.generation,
        sessionEpoch: ProfileRuntime.nextEpoch,
      );
      await registry.publishDataGeneration(
        profileId: current.profileId,
        baseGeneration: staged.baseGeneration,
        stagedGeneration: staged.generation,
        operationId: operationId,
      );
      published = true;
      ProfileRuntime.publish(candidate);
      // Warming mutates process-global controllers. The new empty generation
      // must already be the registry/runtime authority before any observer can
      // see those values.
      for (final participant in lifecycleParticipants) {
        await participant.initializeCandidate(candidate);
      }
      for (final participant in lifecycleParticipants) {
        await participant.didActivate(candidate);
      }
      await registry.markRestoreCleaned(operationId);
    } catch (_) {
      if (published && candidate != null) {
        ProfileRuntime.publish(candidate);
        for (final participant in lifecycleParticipants) {
          try {
            await participant.rollback(candidate);
          } catch (_) {
            // Publication is authoritative; startup recovery completes cleanup.
          }
        }
      } else {
        for (final participant in lifecycleParticipants.reversed) {
          try {
            await participant.rollback(current);
          } catch (_) {
            // Preserve the original reset error.
          }
        }
      }
      rethrow;
    }
  }

  static String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(256));
    return 'reset-${base64UrlEncode(bytes).replaceAll('=', '')}';
  }
}
