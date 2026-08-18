import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/user_profile.dart';

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

  void onResume() {
    final profile = _profile;
    if (profile?.lockOnResume == true && profile!.hasPin) lock();
  }

  void lock() {
    final profile = _profile;
    if (profile == null) return;
    _timer?.cancel();
    lockedProfileId.value = profile.id;
    authorityRevision.value++;
    _publishPrivacy();
  }

  void unlock(UserProfile profile) {
    activate(profile, unlocked: true);
  }

  void dispose() {
    _timer?.cancel();
    _profile = null;
    lockedProfileId.value = null;
    authorityRevision.value++;
    _publishPrivacy();
  }

  void _arm() {
    _timer?.cancel();
    final minutes = _profile?.inactivityTimeoutMinutes;
    if (_playbackActive || minutes == null || minutes <= 0) return;
    _timer = Timer(Duration(minutes: minutes), lock);
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
                profile?.lockOnResume == true && profile?.hasPin == true,
          })
          .catchError((_) {}),
    );
  }
}
