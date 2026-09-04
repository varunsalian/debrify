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
    if (current.profileId == targetProfileId) {
      if (afterDeactivateBeforeCommit == null &&
          afterAuthorityCommitted == null &&
          afterCommitBeforeInitialize == null) {
        return true;
      }
      switching.value = true;
      try {
        afterAuthorityCommitted?.call();
        for (final participant in participants) {
          await participant.prepareDeactivate(current);
        }
        await afterDeactivateBeforeCommit?.call();
        await afterCommitBeforeInitialize?.call();
        for (final participant in participants) {
          await participant.initializeCandidate(current);
        }
        for (final participant in participants) {
          await participant.didActivate(current);
        }
        return true;
      } catch (_) {
        for (final participant in participants.reversed) {
          try {
            await participant.rollback(current);
          } catch (_) {
            // Preserve the adoption/copy error while restoring every service.
          }
        }
        rethrow;
      } finally {
        switching.value = false;
      }
    }
    final target = await registry.getProfile(targetProfileId);
    if (target == null ||
        !target.isEnabled ||
        target.lifecycle != UserProfileLifecycle.active ||
        target.pinResetRequired) {
      return false;
    }
    if (target.hasPin && (unlock == null || !await unlock(target))) {
      return false;
    }

    final candidate = ProfileScope(
      profileId: target.id,
      dataGeneration: target.visibleDataGeneration,
      sessionEpoch: ProfileRuntime.nextEpoch,
    );
    switching.value = true;
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
      await afterDeactivateBeforeCommit?.call();
      await registry.commitActivation(
        targetProfileId: target.id,
        completeOnboarding: completeOnboarding,
        onAuthorityCommitted: () {
          committed = true;
          afterAuthorityCommitted?.call();
        },
      );
      ProfileRuntime.publish(candidate);
      await afterCommitBeforeInitialize?.call();
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
      if (journalStarted && !committed) await registry.abortActivation();
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
    }
  });

  void dispose() => switching.dispose();
}
