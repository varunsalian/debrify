import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/main_page_bridge.dart';
import '../../services/diagnostic_log.dart';
import '../../services/deep_link_service.dart';
import '../../services/profiles/profile_app_lifecycle_participant.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/connection_resource_service.dart';
import '../../services/profiles/profile_lifecycle.dart';
import '../../services/profiles/profile_lock_controller.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_policy_guard.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/profiles/profile_remote_lease.dart';
import '../../services/remote_control/remote_command_router.dart';
import '../../services/tvos_top_shelf_service.dart';
import '../../services/watched_status_service.dart';
import 'manage_profiles_screen.dart';
import 'profile_gate_looks.dart';
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

@visibleForTesting
Future<bool> switchThenApplySyncedProfileOutcome({
  required ProfileLifecycleCoordinator lifecycle,
  required String replacementProfileId,
  required SyncedProfileOutcomeApply applyOutcome,
}) async {
  final switched = await lifecycle.switchTo(
    replacementProfileId,
    unlock: (_) async => true,
  );
  if (!switched) return false;
  try {
    await applyOutcome();
  } catch (error, stackTrace) {
    debugPrint(
      'Deferred synced profile outcome after switching '
      '(${error.runtimeType})',
    );
    DiagnosticLog.instance.recordError(
      source: 'profiles',
      event: 'synced_profile_outcome_deferred',
      error: error,
      stackTrace: stackTrace,
    );
  }
  return true;
}

final class _PendingSyncedProfileRetirement {
  const _PendingSyncedProfileRetirement({
    required this.profileId,
    required this.applyOutcome,
  });

  final String profileId;
  final SyncedProfileOutcomeApply applyOutcome;
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
  _PendingSyncedProfileRetirement? _pendingSyncedRetirement;

  /// Guards the one retry [_load] gets when it fails before the gate has any
  /// profiles to paint. Cleared on every success.
  bool _retriedLoad = false;
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
      MainPageBridge.switchProfile = _showPickerFor;
      MainPageBridge.retireProfileFromSync = _retireProfileFromSync;
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
    if (MainPageBridge.switchProfile == _showPickerFor) {
      MainPageBridge.switchProfile = null;
    }
    if (MainPageBridge.retireProfileFromSync == _retireProfileFromSync) {
      MainPageBridge.retireProfileFromSync = null;
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
    final List<UserProfile> profiles;
    try {
      await ProfileGateStyle.warm();
      await ProfileGateAlwaysAsk.warm();
      final retiredId = _pendingSyncedRetirement?.profileId;
      profiles = (await ProfileBootstrap.registry.listProfiles())
          .where((profile) => profile.id != retiredId)
          .toList(growable: false);
    } catch (e) {
      debugPrint('ProfileGate: profile load failed — $e');
      // On the FIRST load there is no cached list to fall back on, so giving
      // up here holds the gate on its spinner forever with nothing to retry —
      // the dead screen this handling exists to prevent. Anything in the block
      // above can throw transiently right after an authority hand-off (a
      // preference bound to a scope that just moved, a registry read racing a
      // retirement), so try once more before conceding. A later load failing
      // is harmless: the previous list stays on screen.
      if (_profiles == null && !_retriedLoad && mounted) {
        _retriedLoad = true;
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          unawaited(
            _load(allowSingleProfileAutoEnter: allowSingleProfileAutoEnter),
          );
        });
      }
      return;
    }
    if (!mounted) return;
    _retriedLoad = false;
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
    // Keep the sync policy mirror current for build-path gates (nav, rows).
    ProfilePolicyGuard.updateActiveProfile(
      active.isNotEmpty ? active.first : null,
    );
    if (active.isNotEmpty) {
      ProfileLockController.instance.activate(active.first, unlocked: _entered);
      if (_entered) {
        ProfileRemoteLease.instance.authorize(
          active.first,
          ProfileRuntime.capture(),
        );
        TvosTopShelfService.instance.onProfileUnlocked();
        DeepLinkService().onProfileUnlocked();
        WatchedStatusService.instance.ensureStarted();
      } else {
        ProfileRemoteLease.instance.revoke();
        RemoteCommandRouter().clearProfileSessionState();
      }
    }
  }

  void _showPicker() {
    unawaited(_openPicker());
  }

  Future<bool> _retireProfileFromSync(
    String profileId, {
    required bool delete,
    required SyncedProfileOutcomeApply applyOutcome,
  }) async {
    if (!mounted || !_committed) return false;
    final existing = await ProfileBootstrap.registry.getProfile(profileId);
    if (existing == null) return true;
    if (!delete &&
        (!existing.isEnabled ||
            existing.lifecycle != UserProfileLifecycle.active ||
            existing.pinResetRequired)) {
      return true;
    }
    if (ProfileRuntime.capture().profileId != profileId) {
      await applyOutcome();
      final applied = await ProfileBootstrap.registry.getProfile(profileId);
      return delete
          ? applied == null
          : applied == null ||
                !applied.isEnabled ||
                applied.lifecycle != UserProfileLifecycle.active ||
                applied.pinResetRequired;
    }
    _pendingSyncedRetirement = _PendingSyncedProfileRetirement(
      profileId: profileId,
      applyOutcome: applyOutcome,
    );
    await _openPicker();
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile no longer available')),
    );
    return false;
  }

  Future<void> _showPickerFor(String profileId) async {
    await _openPicker();
    if (!mounted) return;
    final matches = _profiles?.where((profile) => profile.id == profileId);
    if (matches == null || matches.isEmpty) return;
    await _selected(matches.first);
  }

  Future<void> _openPicker() async {
    if (!mounted || !_committed) return;
    // Nothing may sit above the gate while it asks who is watching. A remote
    // profile-graph import hands authority over, which remounts AppInitializer
    // through the gate's epoch key — and the doomed instance's in-flight
    // `_showOnboarding` can still push its route on top of the picker, which
    // reads as a blank screen.
    //
    // Anchored on the gate's OWN route object so popUntil is certain to stop
    // here. Popping by position instead (`isFirst`, or a canPop loop) over-
    // pops: pop() only STARTS the exit animation and leaves the route in
    // history, so the next check still sees it — and the gate removes itself,
    // emptying the navigator.
    final own = ModalRoute.of(context);
    if (own != null && !own.isCurrent) {
      Navigator.of(context).popUntil((route) => identical(route, own));
    }
    setState(() {
      _pinTarget = null;
      _pinForManagement = false;
      _entered = false;
      // The cached list is deliberately KEPT, even though an import can retire
      // the profile it holds. Clearing it first means a `_load` failure below
      // leaves `_profiles == null` with no retry, and build() renders nothing
      // but a spinner forever — trading a stale tile for a dead screen. A
      // stale tile is harmless: `_load` replaces it within a frame or two, and
      // selecting a retired profile just fails the switch.
    });
    ProfileLockController.instance.lock();
    ProfileRemoteLease.instance.revoke();
    RemoteCommandRouter().clearProfileSessionState();
    MainPageBridge.clearProfileSessionState();
    unawaited(TvosTopShelfService.instance.clear());
    // Auto-entering a sole unpinned profile is a launch convenience. An
    // explicit Switch profile request must remain on the picker so its Admin
    // can reach Manage profiles and create the second profile.
    await _load(allowSingleProfileAutoEnter: false);
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
    final retirement = _pendingSyncedRetirement;
    final retiredId = retirement?.profileId;
    if (profile.id != currentId) {
      final switched = retiredId != null && retiredId != profile.id
          ? await switchThenApplySyncedProfileOutcome(
              lifecycle: _lifecycle!,
              replacementProfileId: profile.id,
              applyOutcome: retirement!.applyOutcome,
            )
          : await _lifecycle!.switchTo(profile.id, unlock: (_) async => true);
      if (!switched || !mounted) return;
      if (retiredId != null) _pendingSyncedRetirement = null;
    }
    // Mirror BEFORE the frame that reveals the child tree: build-path gates
    // (nav, rows) must never render one frame under the previous profile's
    // policy across a switch.
    ProfilePolicyGuard.updateActiveProfile(profile);
    setState(() {
      _pinTarget = null;
      _pinForManagement = false;
      _entered = true;
    });
    ProfileLockController.instance.unlock(profile);
    ProfileRemoteLease.instance.authorize(profile, ProfileRuntime.capture());
    TvosTopShelfService.instance.onProfileUnlocked();
    DeepLinkService().onProfileUnlocked();
    // Explicit picker/PIN entry may unlock the already-active profile without
    // running a profile switch reset, so it still requires a forced refresh.
    WatchedStatusService.instance.refreshForActiveProfile();
  }

  Future<ProfilePinVerification> _verifyPin(String pin) async {
    final target = _pinTarget!;
    final locks = ProfileLockController.instance;
    final pendingLock = locks.pendingPinLock(target.id);
    final verification = await _pins!.verify(target.id, pin);
    if (verification.result == ProfilePinResult.verified && mounted) {
      locks.acknowledgeVerifiedPin(target.id, pendingLock);
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

  /// A verified recovery code has already stripped the profile's PIN, so it
  /// proceeds exactly like a successful PIN entry — plus a nudge to set a
  /// replacement.
  Future<ProfileRecoveryResult> _recoverPin(String code) async {
    final target = _pinTarget!;
    final result = await _pins!.verifyRecoveryCode(target.id, code);
    if (result == ProfileRecoveryResult.cleared && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PIN removed. Set a new one (and a new recovery code) in '
            'Manage Profiles.',
          ),
          duration: Duration(seconds: 6),
        ),
      );
      if (_pinForManagement) {
        setState(() {
          _pinTarget = null;
          _pinForManagement = false;
        });
        // Let the recovery dialog's pop land first — opening management from
        // inside onRecovery would push its route on top of the still-open
        // dialog, freezing it beneath the management session. A zero-delay
        // timer runs after the pop's microtask.
        unawaited(
          Future<void>.delayed(
            Duration.zero,
            () => _openManagement(target, pinVerified: true),
          ),
        );
      } else {
        // The PIN is gone whatever happens next; if activation fails, the
        // stale PIN screen would be a dead end, so fall back to the picker.
        setState(() {
          _pinTarget = null;
          _pinForManagement = false;
        });
        await _activate(target);
      }
    }
    return result;
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
        onRecovery: _recoverPin,
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
    switch (ProfileGateStyle.cached) {
      case ProfileGateStyle.classic:
        return ProfilePickerScreen(
          profiles: profiles,
          onSelected: _selected,
          onManage: onManage,
        );
      case ProfileGateStyle.wall:
        return ProfileWallScreen(
          profiles: profiles,
          onSelected: _selected,
          onManage: onManage,
        );
      case ProfileGateStyle.row:
        return ProfileRowGateScreen(
          profiles: profiles,
          onSelected: _selected,
          onManage: onManage,
        );
      case ProfileGateStyle.theater:
        return ProfileTheaterGateScreen(
          profiles: profiles,
          onSelected: _selected,
          onManage: onManage,
        );
      case ProfileGateStyle.marquee:
        return ProfileMarqueeGateScreen(
          profiles: profiles,
          onSelected: _selected,
          onManage: onManage,
        );
      // Stage Cards is the default; an unknown stored value (a future style
      // rolled back) lands here too rather than on a blank screen.
      case ProfileGateStyle.stageCards:
      default:
        return ProfileStageCardsGateScreen(
          profiles: profiles,
          onSelected: _selected,
          onManage: onManage,
        );
    }
  }
}
