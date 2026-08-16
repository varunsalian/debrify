import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/main_page_bridge.dart';
import '../../services/deep_link_service.dart';
import '../../services/profiles/profile_app_lifecycle_participant.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/connection_resource_service.dart';
import '../../services/profiles/profile_lifecycle.dart';
import '../../services/profiles/profile_lock_controller.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/profiles/profile_remote_lease.dart';
import '../../services/remote_control/remote_command_router.dart';
import '../../services/tvos_top_shelf_service.dart';
import 'manage_profiles_screen.dart';
import 'profile_picker_screen.dart';
import 'profile_wall_screen.dart';
import 'profile_pin_screen.dart';

@visibleForTesting
bool shouldAutoEnterSoleProfile(
  List<UserProfile> profiles, {
  required bool allowSingleProfileAutoEnter,
}) {
  if (!allowSingleProfileAutoEnter || profiles.length != 1) return false;
  final profile = profiles.single;
  return !profile.hasPin && !profile.pinResetRequired;
}

class ProfileGate extends StatefulWidget {
  final Widget child;

  const ProfileGate({super.key, required this.child});

  @override
  State<ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<ProfileGate> with WidgetsBindingObserver {
  List<UserProfile>? _profiles;
  UserProfile? _pinTarget;
  bool _pinForManagement = false;
  bool _entered = false;
  late final ProfileLifecycleCoordinator? _lifecycle;
  late final ProfilePinService? _pins;

  bool get _committed => ProfileRuntime.isProfileCommitted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_committed) {
      final registry = ProfileBootstrap.registry;
      _pins = ProfilePinService(registry: registry);
      _lifecycle = ProfileLifecycleCoordinator(
        registry: registry,
        participants: <ProfileLifecycleParticipant>[
          ProfileAppLifecycleParticipant(),
        ],
      );
      ProfileRuntime.scope.addListener(_scopeChanged);
      ProfileLockController.instance.lockedProfileId.addListener(_lockChanged);
      MainPageBridge.showProfilePicker = _showPicker;
      unawaited(_load(allowSingleProfileAutoEnter: true));
    } else {
      _pins = null;
      _lifecycle = null;
      _entered = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_committed) ProfileRuntime.scope.removeListener(_scopeChanged);
    if (_committed) {
      ProfileLockController.instance.lockedProfileId.removeListener(
        _lockChanged,
      );
      ProfileLockController.instance.dispose();
      ProfileRemoteLease.instance.revoke();
      RemoteCommandRouter().clearProfileSessionState();
    }
    if (MainPageBridge.showProfilePicker == _showPicker) {
      MainPageBridge.showProfilePicker = null;
    }
    _lifecycle?.dispose();
    super.dispose();
  }

  void _scopeChanged() {
    if (mounted) setState(() {});
  }

  void _lockChanged() {
    if (!mounted ||
        ProfileLockController.instance.lockedProfileId.value == null) {
      return;
    }
    setState(() {
      _pinTarget = null;
      _pinForManagement = false;
      _entered = false;
    });
    ProfileRemoteLease.instance.revoke();
    RemoteCommandRouter().clearProfileSessionState();
    MainPageBridge.clearProfileSessionState();
    unawaited(TvosTopShelfService.instance.clear());
  }

  Future<void> _load({required bool allowSingleProfileAutoEnter}) async {
    await ProfileGateStyle.warm();
    await ProfileGateAlwaysAsk.warm();
    final profiles = await ProfileBootstrap.registry.listProfiles();
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _entered = shouldAutoEnterSoleProfile(
        profiles,
        // The sole-profile launch convenience is opt-IN now: the gate always
        // asks unless the hub's startup toggle re-enables auto-enter. The
        // caller's argument still outranks everything — an explicit Switch
        // or a lock must land on the picker regardless of the toggle.
        allowSingleProfileAutoEnter:
            allowSingleProfileAutoEnter && !ProfileGateAlwaysAsk.cached,
      );
    });
    if (!_entered) {
      // Startup conveniences were resolved against the last active profile
      // before this gate mounted. Once a picker/PIN is required they are not
      // eligible for a later profile and must be discarded before unlock.
      MainPageBridge.clearProfileSessionState();
    }
    final activeId = ProfileRuntime.capture().profileId;
    final active = profiles.where((profile) => profile.id == activeId);
    if (active.isNotEmpty) {
      ProfileLockController.instance.activate(active.first, unlocked: _entered);
      if (_entered) {
        ProfileRemoteLease.instance.authorize(
          active.first,
          ProfileRuntime.capture(),
        );
        TvosTopShelfService.instance.onProfileUnlocked();
        DeepLinkService().onProfileUnlocked();
      } else {
        ProfileRemoteLease.instance.revoke();
        RemoteCommandRouter().clearProfileSessionState();
      }
    }
  }

  void _showPicker() {
    if (!mounted || !_committed) return;
    setState(() {
      _pinTarget = null;
      _pinForManagement = false;
      _entered = false;
    });
    ProfileLockController.instance.lock();
    ProfileRemoteLease.instance.revoke();
    RemoteCommandRouter().clearProfileSessionState();
    MainPageBridge.clearProfileSessionState();
    unawaited(TvosTopShelfService.instance.clear());
    // Auto-entering a sole unpinned profile is a launch convenience. An
    // explicit Switch profile request must remain on the picker so its Admin
    // can reach Manage profiles and create the second profile.
    unawaited(_load(allowSingleProfileAutoEnter: false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_committed || state != AppLifecycleState.resumed || !_entered) return;
    ProfileLockController.instance.onResume();
  }

  Future<void> _selected(UserProfile profile) async {
    try {
      if (profile.pinResetRequired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('An Admin must reset this profile PIN.'),
          ),
        );
        return;
      }
      if (profile.hasPin) {
        setState(() {
          _pinForManagement = false;
          _pinTarget = profile;
        });
        return;
      }
      await _activate(profile);
    } on ResourceAuthorizationException catch (error) {
      debugPrint('Profile activation was revoked (${error.runtimeType})');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not switch profile. Try again.')),
      );
    } on StateError catch (error) {
      debugPrint('Profile activation failed (${error.runtimeType})');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not switch profile. Try again.')),
      );
    }
  }

  Future<void> _activate(UserProfile profile) async {
    final currentId = ProfileRuntime.capture().profileId;
    if (profile.id != currentId) {
      final switched = await _lifecycle!.switchTo(
        profile.id,
        unlock: (_) async => true,
      );
      if (!switched || !mounted) return;
    }
    setState(() {
      _pinTarget = null;
      _pinForManagement = false;
      _entered = true;
    });
    ProfileLockController.instance.unlock(profile);
    ProfileRemoteLease.instance.authorize(profile, ProfileRuntime.capture());
    TvosTopShelfService.instance.onProfileUnlocked();
    DeepLinkService().onProfileUnlocked();
  }

  Future<ProfilePinVerification> _verifyPin(String pin) async {
    final target = _pinTarget!;
    final verification = await _pins!.verify(target.id, pin);
    if (verification.result == ProfilePinResult.verified && mounted) {
      if (_pinForManagement) {
        setState(() {
          _pinTarget = null;
          _pinForManagement = false;
        });
        await _openManagement(target, pinVerified: true);
      } else {
        await _activate(target);
      }
    }
    return verification;
  }

  Future<void> _manage() async {
    final authorization = await ProfileAuthorizationContext.capture(
      ProfileBootstrap.registry,
    );
    final profile = await authorization.validate(ProfileBootstrap.registry);
    if (!profile.allows(ProfileFeature.manageProfiles) || !mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ManageProfilesScreen(
          registry: ProfileBootstrap.registry,
          authorization: authorization,
        ),
      ),
    );
    await _load(allowSingleProfileAutoEnter: false);
  }

  Future<void> _requestManage(UserProfile active) async {
    if (active.hasPin) {
      setState(() {
        _pinForManagement = true;
        _pinTarget = active;
      });
      return;
    }
    await _openManagement(active, pinVerified: false);
  }

  Future<void> _openManagement(
    UserProfile active, {
    required bool pinVerified,
  }) async {
    try {
      await ProfileAuthorizationContext.unlockActiveAdminForManagement(
        ProfileBootstrap.registry,
        expectedProfile: active,
        pinVerified: pinVerified,
      );
      if (!mounted) return;
      await _manage();
    } catch (_) {
      ProfileLockController.instance.lock();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile management is not authorized')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_committed || _entered) {
      final epoch = _committed ? ProfileRuntime.capture().sessionEpoch : 0;
      final child = KeyedSubtree(
        key: ValueKey<int>(epoch),
        child: widget.child,
      );
      if (!_committed) return child;
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => ProfileLockController.instance.userActivity(),
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent) {
              ProfileLockController.instance.userActivity();
            }
            return KeyEventResult.ignored;
          },
          child: child,
        ),
      );
    }
    final target = _pinTarget;
    if (target != null) {
      return ProfilePinScreen(
        profile: target,
        onSubmit: _verifyPin,
        onCancel: () => setState(() {
          _pinTarget = null;
          _pinForManagement = false;
        }),
      );
    }
    final profiles = _profiles;
    if (profiles == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final active = profiles.where(
      (profile) => profile.id == ProfileRuntime.capture().profileId,
    );
    final activeProfile = active.isEmpty ? null : active.first;
    // Both pickers share the same callbacks, so the management authorization
    // ladder (_requestManage -> PIN -> unlockActiveAdminForManagement) is
    // identical whichever style renders.
    final onManage =
        activeProfile?.allows(ProfileFeature.manageProfiles) == true
        ? () => _requestManage(activeProfile!)
        : null;
    if (ProfileGateStyle.cached == ProfileGateStyle.wall) {
      return ProfileWallScreen(
        profiles: profiles,
        onSelected: _selected,
        onManage: onManage,
      );
    }
    return ProfilePickerScreen(
      profiles: profiles,
      onSelected: _selected,
      onManage: onManage,
    );
  }
}
