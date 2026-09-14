import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/user_profile.dart';
import '../diagnostic_log.dart';

/// One foreground-session lock authority. Durable jobs deliberately do not
/// participate: locking is a local UI boundary, not job cancellation.
class ProfileLockController {
  ProfileLockController._();

  static final ProfileLockController instance = ProfileLockController._();
  static const MethodChannel _privacy = MethodChannel(
    'com.debrify.app/profile_privacy',
  );

  final ValueNotifier<String?> lockedProfileId = ValueNotifier<String?>(null);
  final ValueNotifier<int> authorityRevision = ValueNotifier<int>(0);
  Timer? _timer;
  UserProfile? _profile;
  bool _playbackActive = false;
  final Set<Object> _nativePlaybackOwners = <Object>{};
  final Map<String, Object> _lockOnNextResume = <String, Object>{};

  bool get hasActivatedProfile => _profile != null;
  bool get isUnlocked => _profile != null && lockedProfileId.value == null;

  void activate(UserProfile profile, {required bool unlocked}) {
    _profile = profile;
    lockedProfileId.value = unlocked ? null : profile.id;
    authorityRevision.value++;
    _arm();
    _publishPrivacy();
  }

  void userActivity() {
    if (lockedProfileId.value == null) _arm();
  }

  void setPlaybackActive(bool active) {
    _playbackActive = active;
    if (active) {
      _timer?.cancel();
    } else {
      _arm();
    }
  }

  /// Separate owners prevent a stale native finish (or a disposed Flutter
  /// player) from rearming inactivity during a newer native watch.
  Object beginNativePlayback() {
    final owner = Object();
    _nativePlaybackOwners.add(owner);
    _timer?.cancel();
    return owner;
  }

  void endNativePlayback(Object owner) {
    if (_nativePlaybackOwners.remove(owner)) _arm();
  }

  void onResume() {
    final profile = _profile;
    if (profile == null) return;
    final oneShot = _lockOnNextResume.remove(profile.id) != null;
    if (!profile.hasPin) return;
    if (oneShot || profile.lockOnResume) {
      lock(reason: oneShot ? 'pin_changed' : 'resume_policy');
    }
  }

  /// A synchronized PIN replacement must not interrupt the current unlocked
  /// session. The new verifier takes effect at the next foreground boundary.
  void armLockOnNextResume(String profileId) {
    if (profileId.isNotEmpty) {
      _lockOnNextResume[profileId] = Object();
      _publishPrivacy();
    }
  }

  /// Capture before starting PIN verification, never after its async work.
  Object? pendingPinLock(String profileId) => _lockOnNextResume[profileId];

  /// A successful verification satisfies a previously pending sync lock.
  /// A replacement received during verification must retain its own lock.
  /// Generic unlocks and metadata refreshes deliberately do not acknowledge it.
  void acknowledgeVerifiedPin(String profileId, Object? pendingLock) {
    if (pendingLock != null &&
        identical(_lockOnNextResume[profileId], pendingLock)) {
      _lockOnNextResume.remove(profileId);
      _publishPrivacy();
    }
  }

  void lock({String reason = 'explicit'}) {
    final profile = _profile;
    if (profile == null) return;
    _timer?.cancel();
    DiagnosticLog.instance.recordEvent(
      source: 'profile_lock',
      durable: true,
      event: 'locked',
      fields: <String, Object?>{
        'reason': DiagnosticLabel(reason),
        'nativePlaybackActive': _nativePlaybackOwners.isNotEmpty,
        'flutterPlaybackActive': _playbackActive,
      },
    );
    lockedProfileId.value = profile.id;
    authorityRevision.value++;
    _publishPrivacy();
  }

  void unlock(UserProfile profile) {
    activate(profile, unlocked: true);
  }

  /// Refreshes non-authority profile metadata without changing lock state.
  ///
  /// Async settings saves use this instead of [unlock]: a lock or profile
  /// switch may have happened while their database/checkpoint work was in
  /// flight, and completion must never reopen the old session.
  bool refreshProfileIfCurrent(UserProfile profile) {
    if (_profile?.id != profile.id) return false;
    _profile = profile;
    if (lockedProfileId.value == null) {
      _arm();
    } else {
      _timer?.cancel();
    }
    _publishPrivacy();
    return true;
  }

  void dispose() {
    _timer?.cancel();
    _profile = null;
    _playbackActive = false;
    _nativePlaybackOwners.clear();
    _lockOnNextResume.clear();
    lockedProfileId.value = null;
    authorityRevision.value++;
    _publishPrivacy();
  }

  void _arm() {
    _timer?.cancel();
    final minutes = _profile?.inactivityTimeoutMinutes;
    if (_playbackActive ||
        _nativePlaybackOwners.isNotEmpty ||
        minutes == null ||
        minutes <= 0) {
      return;
    }
    _timer = Timer(
      Duration(minutes: minutes),
      () => lock(reason: 'inactivity'),
    );
  }

  void _publishPrivacy() {
    final profile = _profile;
    unawaited(
      _privacy
          .invokeMethod<void>('setSensitive', <String, Object?>{
            // No active profile is sensitive too: startup/teardown must fail
            // closed until the committed gate publishes an unlocked profile.
            'sensitive': !isUnlocked,
            'protectOnBackground':
                profile?.hasPin == true &&
                (profile?.lockOnResume == true ||
                    _lockOnNextResume.containsKey(profile?.id)),
          })
          .catchError((_) {}),
    );
  }
}
