import '../local_validation_diagnostics.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../../models/profiles/user_profile.dart';
import 'profile_registry.dart';
import 'profile_runtime.dart';
import 'profile_scope.dart';

abstract interface class ProfileLifecycleParticipant {
  Future<void> prepareDeactivate(ProfileScope current);
  Future<void> initializeCandidate(ProfileScope candidate);
  Future<void> didActivate(ProfileScope active);
  Future<void> rollback(ProfileScope restored);
}

class ProfileLifecycleCoordinator {
  final ProfileRegistry registry;
  final List<ProfileLifecycleParticipant> participants;
  final Lock _switchLock = Lock();
  final ValueNotifier<bool> switching = ValueNotifier<bool>(false);

  ProfileLifecycleCoordinator({
    required this.registry,
    this.participants = const <ProfileLifecycleParticipant>[],
  });

  Future<bool> switchTo(
    String targetProfileId, {
    Future<bool> Function(UserProfile target)? unlock,
    bool completeOnboarding = false,
    Future<void> Function()? afterDeactivateBeforeCommit,
    void Function()? afterAuthorityCommitted,
    Future<void> Function()? afterCommitBeforeInitialize,
  }) => _switchLock.synchronized(() async {
    final current = ProfileRuntime.capture();
    final target = await registry.getProfile(targetProfileId);
    if (target == null ||
        !target.isEnabled ||
        target.lifecycle != UserProfileLifecycle.active ||
        target.pinResetRequired) {
      return false;
    }
    final sameProfile = current.profileId == targetProfileId;
    if (sameProfile &&
        current.dataGeneration == target.visibleDataGeneration &&
        !completeOnboarding &&
        afterDeactivateBeforeCommit == null &&
        afterAuthorityCommitted == null &&
        afterCommitBeforeInitialize == null) {
      return true;
    }
    if (!sameProfile &&
        target.hasPin &&
        (unlock == null || !await unlock(target))) {
      return false;
    }

    var candidate = ProfileScope(
      profileId: target.id,
      dataGeneration: target.visibleDataGeneration,
      sessionEpoch: ProfileRuntime.nextEpoch,
    );
    switching.value = true;
    LocalValidationDiagnostics.event('profile_switch_started', {
      'sameProfile': sameProfile,
    });
    var journalStarted = false;
    var committed = false;
    try {
      await registry.beginActivation(
        previousProfileId: current.profileId,
        targetProfileId: target.id,
        nextSessionEpoch: candidate.sessionEpoch,
      );
      journalStarted = true;
      for (final participant in participants) {
        await participant.prepareDeactivate(current);
      }
      // Adoption uses this drained, still-pre-commit edge to finish replacing
      // the target's database bytes. A failure here can safely abort back to
      // the current profile rather than exposing a half-copied target.
      LocalValidationDiagnostics.event('profile_deactivated');
      await afterDeactivateBeforeCommit?.call();
      // The drained hook may have published a new generation for this same
      // identity. Build the scope from the final registry row, not the picker.
      final ready = await registry.getProfile(target.id);
      if (ready == null ||
          !ready.isEnabled ||
          ready.lifecycle != UserProfileLifecycle.active ||
          ready.pinResetRequired) {
        throw StateError('Activation target is unavailable');
      }
      candidate = ProfileScope(
        profileId: ready.id,
        dataGeneration: ready.visibleDataGeneration,
        sessionEpoch: candidate.sessionEpoch,
      );
      await registry.commitActivation(
        targetProfileId: target.id,
        completeOnboarding: completeOnboarding,
        onAuthorityCommitted: () {
          committed = true;
          ProfileRuntime.publish(candidate);
          LocalValidationDiagnostics.event('profile_authority_committed');
          afterAuthorityCommitted?.call();
        },
      );
      await afterCommitBeforeInitialize?.call();
      LocalValidationDiagnostics.event('profile_warm_started');
      // Candidate warming touches process-global caches and controllers. Do it
      // only after registry and runtime authority agree on the target; no
      // observer can see B's state while A is still authoritative.
      for (final participant in participants) {
        await participant.initializeCandidate(candidate);
      }
      for (final participant in participants) {
        await participant.didActivate(candidate);
      }
      return true;
    } catch (_) {
      if (journalStarted && !committed) {
        try {
          await registry.abortActivation();
        } catch (abortError) {
          // Cleanup is best effort; retain the initiating error and restore
          // every participant even if the database/checkpoint is unavailable.
          try {
            debugPrint(
              'Profile activation abort failed: ${abortError.runtimeType}',
            );
          } catch (_) {}
        }
      }
      // Once the registry commit succeeds, the target is authoritative. Never
      // warm the previous profile underneath that authority: roll the process
      // forward to the committed target and let fail-closed native readers stay
      // unavailable until their projection can be republished.
      final restored = committed ? candidate : current;
      if (committed) ProfileRuntime.publish(candidate);
      for (final participant in participants.reversed) {
        try {
          await participant.rollback(restored);
        } catch (_) {
          // Preserve the original activation error and continue restoring.
        }
      }
      rethrow;
    } finally {
      switching.value = false;
      LocalValidationDiagnostics.event('profile_switch_finished', {
        'committed': committed,
      });
    }
  });

  void dispose() => switching.dispose();
}
