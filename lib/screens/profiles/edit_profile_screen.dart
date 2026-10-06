import 'package:debrify/features/edit_profile/models/edit_profile_tv_section.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/profiles/user_profile.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/services/profiles/profile_engine_assignment_service.dart';
import 'package:debrify/services/profiles/profile_pin_service.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/profiles/profile_art.dart';
import 'package:debrify/widgets/profiles/profile_avatar_view.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 10),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.8,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (PlatformUtil.isTelevision)
      return _sections.tvEditor.buildTvEditor(context);

    final editableFeatures = ProfileFeature.values.where(
      (feature) =>
          feature != ProfileFeature.manageProfiles ||
          _owners.form.role == UserProfileRole.admin,
    );
    return PopScope(
      canPop: !_owners.form.saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.profile == null ? 'Create profile' : 'Edit profile',
          ),
          actions: [
            TextButton(
              onPressed: _owners.form.saving ? null : _sections.save.save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Focus(
          descendantsAreFocusable: !_owners.form.saving,
          descendantsAreTraversable: !_owners.form.saving,
          child: AbsorbPointer(
            absorbing: _owners.form.saving,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_owners.form.saving) const LinearProgressIndicator(),
                _sectionLabel('Avatar'),
                _buildAvatarSection(),
                _sectionLabel('Identity'),
                TvTextField(
                  controller: _owners.form.name,
                  autofocus: true,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(40),
                  ],
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (widget.profile == null)
                  SwitchListTile(
                    value: _owners.form.copyDefaults,
                    title: const Text('Copy appearance and playback defaults'),
                    subtitle: const Text(
                      'Does not copy accounts, history, downloads, paths, or IDs.',
                    ),
                    onChanged: (value) =>
                        setState(() => _owners.form.copyDefaults = value),
                  ),
                _sectionLabel('Role'),
                _buildRoleCards(),
                if (EditProfileScreen.showFeaturePolicyControls) ...[
                  const SizedBox(height: 12),
                  for (final feature in editableFeatures)
                    CheckboxListTile(
                      value:
                          _owners.form.features.contains(feature) &&
                          ProfilePolicy(
                            enabled: _owners.form.features,
                          ).allows(_owners.form.role, feature),
                      title: Text(_featureLabel(feature)),
                      onChanged: (enabled) {
                        setState(() {
                          if (enabled == true) {
                            _owners.form.features.add(feature);
                          } else {
                            _owners.form.features.remove(feature);
                          }
                        });
                      },
                    ),
                ],
                _sectionLabel('Lock'),
                TvTextField(
                  controller: _owners.form.pin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: InputDecoration(
                    labelText: widget.profile?.hasPin == true
                        ? 'New PIN (leave blank to keep current)'
                        : 'PIN (optional)',
                  ),
                ),
                if (widget.profile?.hasPin == true ||
                    widget.profile?.pinResetRequired == true)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _owners.form.saving
                          ? null
                          : _sections.adminActions.removePinAsAdmin,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text('Admin reset: remove PIN'),
                    ),
                  ),
                SwitchListTile(
                  value: _owners.form.lockOnResume,
                  title: const Text('Lock when the app resumes'),
                  onChanged: (value) =>
                      setState(() => _owners.form.lockOnResume = value),
                ),
                DropdownButtonFormField<int>(
                  initialValue: _owners.form.inactivityMinutes,
                  decoration: const InputDecoration(labelText: 'Auto-lock'),
                  items: const <DropdownMenuItem<int>>[
                    DropdownMenuItem(value: 0, child: Text('Never')),
                    DropdownMenuItem(value: 5, child: Text('After 5 minutes')),
                    DropdownMenuItem(
                      value: 15,
                      child: Text('After 15 minutes'),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text('After 30 minutes'),
                    ),
                    DropdownMenuItem(value: 60, child: Text('After 1 hour')),
                  ],
                  onChanged: (value) => setState(
                    () => _owners.form.inactivityMinutes = value ?? 0,
                  ),
                ),
                _sectionLabel('Access'),
                if (_owners.access.setupLoadError != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(_owners.access.setupLoadError!),
                    trailing: TextButton(
                      onPressed: _sections.setup.loadSetupOptions,
                      child: const Text('Retry'),
                    ),
                  )
                else if (_owners.access.engines == null)
                  const LinearProgressIndicator()
                else ...[
                  _sections.access.buildEngineGroup(),
                  ..._sections.access.buildConnectionGroups(),
                ],
                if (widget.profile != null) ...[
                  _sectionLabel('Data'),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Diagnostics'),
                    subtitle: const Text(
                      'Registry, generation and lease state',
                    ),
                    onTap: _sections.adminActions.showDiagnostics,
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    final pending = _owners.form.pendingAvatarBytes;
    final userImages = ProfileAvatarPolicy.userImagesSupported;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                width: 84,
                height: 84,
                child: pending != null
                    ? Image.memory(
                        pending,
                        fit: BoxFit.cover,
                        cacheWidth: 168,
                        cacheHeight: 168,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: Color(0xFF31435F),
                          child: Icon(Icons.broken_image_outlined),
                        ),
                      )
                    : ProfileAvatarView(
                        // A brand-new profile has no id yet; any safe id maps
                        // to a nonexistent directory and the view falls back.
                        profileId: widget.profile?.id ?? 'staging-preview',
                        avatarKey: _owners.form.avatarKey,
                        role: _owners.form.role,
                        name: _owners.form.name.text.isEmpty
                            ? '?'
                            : _owners.form.name.text,
                        focused: true,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (userImages)
                    OutlinedButton.icon(
                      onPressed: _owners.form.saving
                          ? null
                          : _sections.avatar.pickAvatarImage,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text(
                        'Choose image or GIF (this device only)',
                      ),
                    ),
                  if (pending != null)
                    TextButton.icon(
                      onPressed: _owners.form.saving
                          ? null
                          : () => setState(
                              () => _owners.form.pendingAvatarBytes = null,
                            ),
                      icon: const Icon(Icons.undo_rounded, size: 18),
                      label: const Text('Discard picked image'),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final art in ProfileArtRegistry.all)
              _artTile(
                key: 'art:${art.id}',
                tooltip: art.label,
                child: ProfileAvatarView(
                  profileId: widget.profile?.id ?? 'staging-preview',
                  avatarKey: 'art:${art.id}',
                  role: _owners.form.role,
                  name: art.label,
                ),
              ),
            for (final iconKey in ProfileAvatar.legacyIconIds)
              _artTile(
                key: iconKey,
                tooltip: iconKey,
                child: ProfileAvatarView(
                  profileId: widget.profile?.id ?? 'staging-preview',
                  avatarKey: iconKey,
                  role: _owners.form.role,
                  name: iconKey,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _artTile({
    required String key,
    required String tooltip,
    required Widget child,
  }) {
    final selected =
        _owners.form.pendingAvatarBytes == null &&
        _owners.form.avatarKey == key;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _owners.form.saving
            ? null
            : () => setState(() {
                _owners.form.avatarKey = key;
                _owners.form.pendingAvatarBytes = null;
              }),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              width: 2.5,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }

  Widget _buildRoleCards() {
    const descriptions = <UserProfileRole, (String, String)>{
      UserProfileRole.admin: (
        'Admin',
        'Full control, including profiles and connections',
      ),
      UserProfileRole.member: ('Member', 'Everything except managing profiles'),
      UserProfileRole.child: ('Kid', 'Limited features, no adult content'),
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 560;
        final cards = [
          for (final role in UserProfileRole.values)
            _roleCard(
              role,
              descriptions[role]!.$1,
              descriptions[role]!.$2,
              horizontal,
            ),
        ];
        return horizontal
            ? Row(children: [for (final card in cards) Expanded(child: card)])
            : Column(children: cards);
      },
    );
  }

  Widget _roleCard(
    UserProfileRole role,
    String title,
    String description,
    bool horizontal,
  ) {
    final selected = _owners.form.role == role;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        right: horizontal ? 8 : 0,
        bottom: horizontal ? 0 : 8,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _owners.form.saving
            ? null
            : () => _sections.selection.setRole(role),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerHighest.withValues(alpha: .45),
            border: Border.all(
              width: 2,
              color: selected ? colors.primary : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: .7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _featureLabel(ProfileFeature feature) {
    final spaced = feature.name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    );
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}
