import 'package:debrify/features/edit_profile/models/edit_profile_tv_section.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:flutter/material.dart';

/// The profile create/edit form, in six labelled sections: Avatar, Identity,
/// Role, Lock, Access, Data. The sectioning is presentation only — what a save
/// writes is unchanged and pinned by tests.
class EditProfileScreen extends StatefulWidget {
  final ProfileRegistry registry;
  final ProfilePinService pins;
  final ProfileAuthorizationContext authorization;
  final UserProfile? profile;

  @visibleForTesting
  final Future<(List<ConnectionResource>, List<ProfileEngineAssignment>)>
  Function()?
  setupOptionsLoader;

  const EditProfileScreen({
    super.key,
    required this.registry,
    required this.pins,
    required this.authorization,
    this.profile,
    this.setupOptionsLoader,
  });

  /// Whether the raw per-feature policy editor is shown on the phone form.
  /// Off pending its own redesign — until then **role is the feature-level
  /// control** there, and the questionnaire (or the TV Pages section) is the
  /// policy author.
  @visibleForTesting
  static const bool showFeaturePolicyControls = false;

  /// The policy a save writes. Extracted so the rule is stated once and can
  /// be pinned by a test.
  ///
  /// [controlsShown] is whether a feature-level control was actually visible
  /// AND used this session (the TV Pages section sets it on first toggle).
  /// While no control was touched, a CREATE seeds the role DEFAULTS and an
  /// EDIT PRESERVES what is stored. The old `allAllowedFor` rewrite silently
  /// un-restricted a configured profile on any avatar/PIN edit, which is
  /// exactly the clobber a hidden control must never perform.
  @visibleForTesting
  static ProfilePolicy policyFor({
    required UserProfileRole role,
    required Set<ProfileFeature> selected,
    ProfilePolicy? existing,
    bool controlsShown = showFeaturePolicyControls,
  }) {
    if (controlsShown) return ProfilePolicy(enabled: selected);
    if (existing != null) return existing;
    return ProfilePolicy.defaultsFor(role);
  }

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  // One node per rail section, plus the rail's Save item at the end.

  // Where downloads/remote started, so their paired features (recordings,
  // remoteTransfer) follow the toggle only when the answer actually MOVED —
  // an untouched save must not re-couple a policy the old feature matrix
  // split (mirrors ProfileSetupFlow._seedDownloads/_seedRemote).

  final EditProfileOwners _owners = EditProfileOwners();
  EditProfileSections? _composition;
  EditProfileSections get _sections => _composition ??= EditProfileSections(
    EditProfileDependencies(
      owners: _owners,
      sections: () => _composition!,
      registry: () => widget.registry,
      pins: () => widget.pins,
      profile: () => widget.profile,
      setupOptionsLoader: () => widget.setupOptionsLoader,
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      readAuthorization: () => _authorization,
      writeAuthorization: (value) => _authorization = value,
      readShowFeaturePolicyControls: () =>
          EditProfileScreen.showFeaturePolicyControls,
      policyFor: EditProfileScreen.policyFor,
    ),
  );
  late ProfileAuthorizationContext _authorization = widget.authorization;

  @override
  void initState() {
    super.initState();
    _owners.tv.tvTabFocusNodes = [
      for (final section in EditProfileTvSection.values)
        FocusNode(debugLabel: 'Edit profile ${section.name} tab'),
      FocusNode(debugLabel: 'Edit profile save'),
    ];
    final profile = widget.profile;
    _owners.form.name = TextEditingController(text: profile?.name ?? '');
    _owners.form.role = profile?.role ?? UserProfileRole.member;
    // Always the policy this screen will WRITE (policyFor: stored policy on
    // edit, role defaults on create) — grant masks derive from _features, so
    // seeding it from the role CEILING would hand every newly ticked
    // resource writeRemote regardless of the profile's remote answer.
    _owners.form.features = Set<ProfileFeature>.from(
      profile?.policy.enabled ??
          ProfilePolicy.defaultsFor(_owners.form.role).enabled,
    );
    _owners.form.seedDownloads = _owners.form.features.contains(
      ProfileFeature.downloads,
    );
    _owners.form.seedRemote = _owners.form.features.contains(
      ProfileFeature.remoteControl,
    );
    _owners.form.lockOnResume = profile?.lockOnResume ?? false;
    _owners.form.inactivityMinutes = profile?.inactivityTimeoutMinutes ?? 0;
    _owners.form.avatarKey =
        profile?.avatarKey ??
        (profile?.role == UserProfileRole.child ? 'child' : 'person');
    _sections.setup.loadSetupOptions();
  }

  @override
  void dispose() {
    for (final node in _owners.tv.tvTabFocusNodes) {
      node.dispose();
    }
    _owners.tv.tvContentFocus.dispose();
    _owners.tv.tvBackFocus.dispose();
    _owners.form.name.dispose();
    _owners.form.pin
      ..clear()
      ..dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => _sections.phone.build(context);
}
