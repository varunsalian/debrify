import 'package:debrify/features/edit_profile/models/edit_profile_tv_section.dart';
import 'package:debrify/features/edit_profile/presentation/edit_profile_tv_surfaces.dart';
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
import 'package:debrify/utils/tv_keys.dart';
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
    if (PlatformUtil.isTelevision) return _buildTvEditor(context);

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
                  _buildEngineGroup(),
                  ..._buildConnectionGroups(),
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

  Widget _buildTvEditor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_owners.form.saving,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
          leading: Navigator.of(context).canPop()
              ? Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, event) {
                    final direction = _sections.tvNav.tvDirection(event);
                    if (direction == null) return KeyEventResult.ignored;
                    if (direction == TraversalDirection.down ||
                        direction == TraversalDirection.right) {
                      _owners.tv.tvTabFocusNodes[_owners.tv.tvSection.index]
                          .requestFocus();
                    }
                    return KeyEventResult.handled;
                  },
                  child: IconButton(
                    focusNode: _owners.tv.tvBackFocus,
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: _owners.form.saving
                        ? null
                        : () => Navigator.maybePop(context),
                    icon: const BackButtonIcon(),
                  ),
                )
              : null,
          title: Text(
            widget.profile == null ? 'Create profile' : 'Edit profile',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Focus(
            descendantsAreFocusable: !_owners.form.saving,
            descendantsAreTraversable: !_owners.form.saving,
            child: AbsorbPointer(
              absorbing: _owners.form.saving,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 32, 24),
                child: Column(
                  children: [
                    if (_owners.form.saving) const LinearProgressIndicator(),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTvSectionRail(colors),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Focus(
                              focusNode: _owners.tv.tvContentFocus,
                              onKeyEvent: (_, event) {
                                // Let text editing and the TV keyboard consume
                                // caret keys; field edge callbacks own exits.
                                if (FocusManager.instance.primaryFocus?.context
                                        ?.findAncestorWidgetOfExactType<
                                          EditableText
                                        >() !=
                                    null) {
                                  return KeyEventResult.ignored;
                                }
                                final direction = _sections.tvNav.tvDirection(
                                  event,
                                );
                                if (direction == null) {
                                  return KeyEventResult.ignored;
                                }
                                _sections.tvNav.moveTvContent(direction);
                                return KeyEventResult.handled;
                              },
                              // OK enters the pane on key-down; its remaining
                              // repeats must not activate a stock form control.
                              child: TvHeldKeyGuard(
                                child: KeyedSubtree(
                                  key: ValueKey(_owners.tv.tvSection),
                                  child: switch (_owners.tv.tvSection) {
                                    EditProfileTvSection.profile =>
                                      _buildTvProfileSection(),
                                    EditProfileTvSection.pages =>
                                      _buildTvPagesSection(),
                                    EditProfileTvSection.lock =>
                                      _buildTvLockSection(),
                                    EditProfileTvSection.access =>
                                      _buildTvAccessSection(),
                                    EditProfileTvSection.data =>
                                      _buildTvDataSection(),
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvSectionRail(ColorScheme colors) {
    const tabs = <(EditProfileTvSection, IconData, String)>[
      (EditProfileTvSection.profile, Icons.person_rounded, 'PROFILE'),
      (EditProfileTvSection.pages, Icons.grid_view_rounded, 'PAGES'),
      (EditProfileTvSection.access, Icons.group_rounded, 'ACCESS'),
      (EditProfileTvSection.lock, Icons.lock_rounded, 'LOCK'),
      (EditProfileTvSection.data, Icons.shield_rounded, 'DATA'),
    ];
    final saveIndex = tabs.length;
    Widget railItem({
      required int index,
      required Widget child,
      required VoidCallback? onPressed,
      Key? key,
      bool selected = false,
    }) => SizedBox(
      height: 56,
      child: editProfileTvActionSurface(
        key: key,
        selected: selected,
        autofocus: index == 0,
        focusNode: _owners.tv.tvTabFocusNodes[index],
        onKeyEvent: (_, event) => _sections.tvNav.handleTvRailKey(index, event),
        onPressed: onPressed,
        child: child,
      ),
    );
    Widget railLabel(IconData icon, String label) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
        ],
      ),
    );
    return Container(
      width: 200,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .45)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  for (var index = 0; index < tabs.length; index++) ...[
                    railItem(
                      index: index,
                      key: ValueKey('tv-profile-tab-${tabs[index].$1.name}'),
                      selected: _owners.tv.tvSection == tabs[index].$1,
                      // Up/down previews sections; OK or a click enters the pane.
                      onPressed: () {
                        _sections.tvNav.selectTvSection(tabs[index].$1);
                        _owners.tv.tvTabFocusNodes[index].requestFocus();
                        _sections.tvNav.focusTvContent();
                      },
                      child: railLabel(tabs[index].$2, tabs[index].$3),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const Spacer(),
                  railItem(
                    index: saveIndex,
                    key: const ValueKey('tv-profile-save'),
                    onPressed: _owners.form.saving ? null : _sections.save.save,
                    child: railLabel(
                      Icons.check_rounded,
                      _owners.form.saving ? 'SAVING…' : 'SAVE',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvPagesSection() {
    bool on(ProfileFeature feature) => ProfilePolicy(
      enabled: _owners.form.features,
    ).allows(_owners.form.role, feature);
    void toggle(ProfileFeature feature) {
      if (_owners.form.saving) return;
      setState(() {
        _owners.form.policyTouched = true;
        if (!_owners.form.features.remove(feature))
          _owners.form.features.add(feature);
      });
    }

    Widget group(String label) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.8,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
    Widget tile(ProfileFeature feature, String title, String description) {
      final enabled = on(feature);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: editProfileTvActionSurface(
          key: ValueKey('tv-pages-${feature.name}'),
          onPressed: () => toggle(feature),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Icon(
                  enabled
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 28,
                  color: enabled
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: .35),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: _tvPanel(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pages & abilities',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose what this profile sees and can do. Playback always '
                  'keeps working through its granted sources.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                group('SEARCH'),
                tile(
                  ProfileFeature.keywordSearch,
                  'Keyword search',
                  'Raw release search across torrent engines. Off = search '
                      'by title only.',
                ),
                group('SOURCE PAGES'),
                tile(
                  ProfileFeature.debrifyTv,
                  'Debrify TV',
                  'Channels curated on this device.',
                ),
                tile(
                  ProfileFeature.stremioTv,
                  'Stremio TV',
                  'Addon live channels.',
                ),
                tile(ProfileFeature.iptv, 'Live TV', 'IPTV playlists & guide.'),
                tile(ProfileFeature.youtube, 'YouTube', 'The YouTube tab.'),
                group('ABILITIES'),
                tile(
                  ProfileFeature.downloads,
                  'Download & record',
                  "Save things offline and use the DVR. Uses this device's "
                      "storage and your accounts' quotas.",
                ),
                tile(
                  ProfileFeature.remoteControl,
                  'Remote',
                  'Control other Debrify devices and send this setup to '
                      'them.',
                ),
                tile(
                  ProfileFeature.addonsAndEngines,
                  'Manage own sources',
                  'Install or remove their own addons and torrent engines.',
                ),
                tile(
                  ProfileFeature.cloudFiles,
                  'Cloud files',
                  'Browse the raw file lists on connected accounts — '
                      'including yours, if shared.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvProfileSection() {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 230, child: _buildTvProfilePreview(colors)),
        const SizedBox(width: 18),
        Expanded(
          child: _tvPanel(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Choose an avatar',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (ProfileAvatarPolicy.userImagesSupported)
                        editProfileEnsureVisibleOnFocus(
                          child: OutlinedButton.icon(
                            onPressed: _owners.form.saving
                                ? null
                                : _sections.avatar.pickAvatarImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text(
                              'Choose image or GIF (this device only)',
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_owners.form.pendingAvatarBytes != null &&
                      ProfileAvatarPolicy.userImagesSupported)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _owners.form.saving
                            ? null
                            : () => setState(
                                () => _owners.form.pendingAvatarBytes = null,
                              ),
                        icon: const Icon(Icons.undo_rounded),
                        label: const Text('Discard picked image'),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final art in ProfileArtRegistry.all)
                        _tvAvatarTile(
                          keyName: 'art:${art.id}',
                          label: art.label,
                        ),
                      for (final iconKey in ProfileAvatar.legacyIconIds)
                        _tvAvatarTile(keyName: iconKey, label: iconKey),
                    ],
                  ),
                  const SizedBox(height: 22),
                  Text('Name', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TvTextField(
                    key: const ValueKey('tv-profile-name'),
                    controller: _owners.form.name,
                    onLeftArrow: _sections.tvNav.returnToTvRail,
                    onRightArrow: () =>
                        _sections.tvNav.moveTvContent(TraversalDirection.right),
                    onUpArrow: () =>
                        _sections.tvNav.moveTvContent(TraversalDirection.up),
                    onDownArrow: () =>
                        _sections.tvNav.moveTvContent(TraversalDirection.down),
                    onChanged: (_) => setState(() {}),
                    inputFormatters: <TextInputFormatter>[
                      LengthLimitingTextInputFormatter(40),
                    ],
                    decoration: const InputDecoration(hintText: 'Profile name'),
                  ),
                  const SizedBox(height: 20),
                  Text('Role', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _buildTvRoleCards(),
                  if (widget.profile == null) ...[
                    const SizedBox(height: 14),
                    editProfileEnsureVisibleOnFocus(
                      child: SwitchListTile(
                        value: _owners.form.copyDefaults,
                        title: const Text(
                          'Copy appearance and playback defaults',
                        ),
                        onChanged: (value) =>
                            setState(() => _owners.form.copyDefaults = value),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTvProfilePreview(ColorScheme colors) => _tvPanel(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 420;
        final avatarSize = compact ? 118.0 : 164.0;
        return Padding(
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(compact ? 22 : 28),
                child: SizedBox(
                  width: avatarSize,
                  height: avatarSize,
                  child: _owners.form.pendingAvatarBytes != null
                      ? Image.memory(
                          _owners.form.pendingAvatarBytes!,
                          fit: BoxFit.cover,
                        )
                      : ProfileAvatarView(
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
              SizedBox(height: compact ? 12 : 24),
              Text(
                _owners.form.name.text.trim().isEmpty
                    ? 'New profile'
                    : _owners.form.name.text.trim(),
                key: const Key('tv-profile-name-preview'),
                textAlign: TextAlign.center,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: compact ? 8 : 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: colors.primary),
                  color: colors.primary.withValues(alpha: .1),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: compact ? 6 : 8,
                  ),
                  child: Text(
                    _owners.form.role == UserProfileRole.child
                        ? 'Kid'
                        : _owners.form.role.name[0].toUpperCase() +
                              _owners.form.role.name.substring(1),
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _tvAvatarTile({required String keyName, required String label}) {
    final selected =
        _owners.form.pendingAvatarBytes == null &&
        _owners.form.avatarKey == keyName;
    return SizedBox(
      width: 78,
      height: 78,
      child: Tooltip(
        message: label,
        child: editProfileTvActionSurface(
          key: ValueKey('tv-profile-avatar-$keyName'),
          selected: selected,
          onPressed: () => setState(() {
            _owners.form.avatarKey = keyName;
            _owners.form.pendingAvatarBytes = null;
          }),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ProfileAvatarView(
              profileId: widget.profile?.id ?? 'staging-preview',
              avatarKey: keyName,
              role: _owners.form.role,
              name: label,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTvRoleCards() {
    const descriptions = <UserProfileRole, (String, String, IconData)>{
      UserProfileRole.admin: (
        'Admin',
        'Full control',
        Icons.admin_panel_settings,
      ),
      UserProfileRole.member: ('Member', 'No profile management', Icons.group),
      UserProfileRole.child: ('Kid', 'Limited content', Icons.child_care),
    };
    Widget card(UserProfileRole role) => editProfileTvActionSurface(
      key: ValueKey('tv-profile-role-${role.name}'),
      selected: _owners.form.role == role,
      onPressed: () => _sections.selection.setRole(role),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(descriptions[role]!.$3, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    descriptions[role]!.$1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    descriptions[role]!.$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // The side rail leaves the form pane narrow on smaller viewports —
        // three cards abreast stop fitting, so they stack.
        if (constraints.maxWidth < 620) {
          return Column(
            children: [
              for (final role in UserProfileRole.values) ...[
                SizedBox(height: 72, width: double.infinity, child: card(role)),
                if (role != UserProfileRole.child) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return SizedBox(
          height: 84,
          child: Row(
            children: [
              for (final role in UserProfileRole.values) ...[
                Expanded(child: card(role)),
                if (role != UserProfileRole.child) const SizedBox(width: 12),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTvLockSection() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: _tvPanel(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile lock',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose when this profile asks for its PIN.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              TvTextField(
                key: const ValueKey('tv-profile-pin'),
                controller: _owners.form.pin,
                onLeftArrow: _sections.tvNav.returnToTvRail,
                onRightArrow: () =>
                    _sections.tvNav.moveTvContent(TraversalDirection.right),
                onUpArrow: () =>
                    _sections.tvNav.moveTvContent(TraversalDirection.up),
                onDownArrow: () =>
                    _sections.tvNav.moveTvContent(TraversalDirection.down),
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
              const SizedBox(height: 16),
              editProfileEnsureVisibleOnFocus(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  value: _owners.form.lockOnResume,
                  title: const Text('Lock when the app resumes'),
                  subtitle: const Text('Require the PIN after leaving Debrify'),
                  onChanged: (value) =>
                      setState(() => _owners.form.lockOnResume = value),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 16),
              EditProfileTvAutoLockField(
                value: _owners.form.inactivityMinutes,
                onChanged: (value) =>
                    setState(() => _owners.form.inactivityMinutes = value),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildTvAccessSection() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: _tvPanel(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile access',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose which engines and connections this profile can use.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              if (_owners.access.setupLoadError != null)
                editProfileEnsureVisibleOnFocus(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(_owners.access.setupLoadError!),
                    trailing: TextButton(
                      onPressed: _sections.setup.loadSetupOptions,
                      child: const Text('Retry'),
                    ),
                  ),
                )
              else if (_owners.access.engines == null)
                const LinearProgressIndicator()
              else ...[
                _buildEngineGroup(),
                ..._buildConnectionGroups(),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildTvDataSection() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: _tvPanel(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile data',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.profile == null
                    ? 'Data tools become available after the profile is created.'
                    : 'Inspect this profile’s registry and session state.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              if (widget.profile != null)
                SizedBox(
                  height: 92,
                  child: editProfileTvActionSurface(
                    onPressed: _sections.adminActions.showDiagnostics,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 32),
                          const SizedBox(width: 18),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Diagnostics',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const Text(
                                  'Registry, generation and lease state',
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 32),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _tvPanel({required Widget child}) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .4),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );

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

  Widget _buildEngineGroup() {
    final engines = _owners.access.engines!;
    final ownEditor = widget.profile?.id == _authorization.profileId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupHeader(
          'Torrent engines',
          selected: _owners.access.selectedEngines.length,
          total: engines.length,
          onAll: engines.isEmpty || ownEditor
              ? null
              : () => setState(
                  () => _owners.access.selectedEngines.addAll(
                    engines.map((engine) => engine.id),
                  ),
                ),
          onNone: engines.isEmpty || ownEditor
              ? null
              : () => setState(_owners.access.selectedEngines.clear),
        ),
        Text(
          ownEditor
              ? 'Manage engines for the active Admin from Torrent Engines.'
              : 'Each profile keeps an independent copy and settings.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (engines.isEmpty)
          const ListTile(
            leading: Icon(Icons.travel_explore_rounded),
            title: Text('No torrent engines installed'),
            subtitle: Text(
              'Install engines in the Admin profile before assigning them.',
            ),
          )
        else
          for (final engine in engines)
            _tvAccessFocusRow(
              key: ValueKey('tv-profile-engine-${engine.id}'),
              interactive: !ownEditor,
              child: CheckboxListTile(
                value: _owners.access.selectedEngines.contains(engine.id),
                title: Text(engine.displayName),
                subtitle: !engine.availableFromManager
                    ? Text(
                        'Installed only in ${widget.profile?.name ?? 'this profile'}',
                      )
                    : null,
                secondary: const Icon(Icons.travel_explore_rounded),
                onChanged: ownEditor
                    ? null
                    : (selected) => setState(() {
                        if (selected == true) {
                          _owners.access.selectedEngines.add(engine.id);
                        } else {
                          _owners.access.selectedEngines.remove(engine.id);
                        }
                      }),
              ),
            ),
      ],
    );
  }

  Widget _tvAccessFocusRow({
    Key? key,
    required bool interactive,
    required Widget child,
  }) {
    if (!PlatformUtil.isTelevision) return child;
    return interactive
        ? editProfileEnsureVisibleOnFocus(key: key, child: child)
        : editProfileTvReadOnlyScrollAnchor(key: key, child: child);
  }

  /// The order and membership of the Access groups. Anything a future type
  /// falls out of lands in the final bucket rather than disappearing.
  static const List<(String, Set<ConnectionResourceType>)> _accessGroups = [
    (
      'Debrid & cloud',
      {
        ConnectionResourceType.realDebrid,
        ConnectionResourceType.torbox,
        ConnectionResourceType.premiumize,
        ConnectionResourceType.allDebrid,
        ConnectionResourceType.pikpak,
        ConnectionResourceType.webDav,
      },
    ),
    ('Addons', {ConnectionResourceType.stremioAddon}),
    (
      'Trackers & lists',
      {
        ConnectionResourceType.trakt,
        ConnectionResourceType.simkl,
        ConnectionResourceType.mdblist,
      },
    ),
    (
      'Live TV & indexers',
      {
        ConnectionResourceType.iptvM3u,
        ConnectionResourceType.iptvXtream,
        ConnectionResourceType.xmltv,
        ConnectionResourceType.jackett,
        ConnectionResourceType.prowlarr,
      },
    ),
  ];

  List<Widget> _buildConnectionGroups() {
    final resources = _owners.access.resources;
    if (resources == null || resources.isEmpty) return const <Widget>[];
    final grouped = <String, List<ConnectionResource>>{};
    for (final resource in resources) {
      // Reddit is a vestige — no sharing section for it.
      if (resource.type == ConnectionResourceType.reddit) continue;
      final label = _accessGroups
          .where((group) => group.$2.contains(resource.type))
          .map((group) => group.$1)
          .firstOrNull;
      grouped.putIfAbsent(label ?? 'Other connections', () => []).add(resource);
    }
    final widgets = <Widget>[
      const SizedBox(height: 10),
      Text(
        'Tracker and cloud access can modify the upstream account.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ];
    for (final (label, _) in _accessGroups) {
      final group = grouped[label];
      if (group != null) widgets.addAll(_connectionGroup(label, group));
    }
    final other = grouped['Other connections'];
    if (other != null) {
      widgets.addAll(_connectionGroup('Other connections', other));
    }
    return widgets;
  }

  List<Widget> _connectionGroup(String label, List<ConnectionResource> group) {
    final selected = group
        .where(
          (resource) => _owners.access.selectedResources.contains(resource.id),
        )
        .length;
    final editable = _sections.selection.editableIn(group).toList();
    return [
      _groupHeader(
        label,
        selected: selected,
        total: group.length,
        onAll: editable.isEmpty
            ? null
            : () => setState(
                () => editable.forEach(_sections.selection.selectResource),
              ),
        onNone: editable.isEmpty
            ? null
            : () => setState(
                () => editable.forEach(_sections.selection.deselectResource),
              ),
      ),
      for (final resource in group) ..._connectionRow(resource),
    ];
  }

  Widget _groupHeader(
    String label, {
    required int selected,
    required int total,
    VoidCallback? onAll,
    VoidCallback? onNone,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 2),
    child: Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        Text(
          '$selected of $total',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: .5),
          ),
        ),
        const Spacer(),
        if (onAll != null)
          TextButton(onPressed: onAll, child: const Text('All')),
        if (onNone != null)
          TextButton(onPressed: onNone, child: const Text('None')),
      ],
    ),
  );

  List<Widget> _connectionRow(ConnectionResource resource) {
    final interactive = resource.ownerProfileId != widget.profile?.id;
    return [
      _tvAccessFocusRow(
        key: ValueKey('tv-profile-connection-${resource.id}'),
        interactive: interactive,
        child: CheckboxListTile(
          value: _owners.access.selectedResources.contains(resource.id),
          title: Text(resource.label),
          subtitle: Text(
            resource.needsReconnect ? 'Reconnect required' : resource.type.name,
          ),
          secondary:
              widget.profile != null &&
                  resource.ownerProfileId != widget.profile!.id &&
                  _owners.form.role != UserProfileRole.child &&
                  _owners.form.features.contains(
                    ProfileFeature.manageConnections,
                  )
              ? IconButton(
                  tooltip: 'Transfer ownership to this profile',
                  onPressed: () =>
                      _sections.adminActions.transferOwnership(resource),
                  icon: const Icon(Icons.swap_horiz_rounded),
                )
              : const Icon(Icons.key_rounded),
          onChanged: interactive
              ? (selected) => setState(() {
                  if (selected == true) {
                    _sections.selection.selectResource(resource);
                  } else {
                    _sections.selection.deselectResource(resource);
                  }
                })
              : null,
        ),
      ),
      // Sharing is BINARY now (profile_features spec): the per-resource
      // permission chips are gone. A newly ticked resource gets the mask
      // DERIVED from the profile's feature policy (_defaultResourcePermissions);
      // an already-granted one keeps its stored mask via the load-time seeding,
      // so explicit grants never churn on an unrelated save.
    ];
  }

  static String _featureLabel(ProfileFeature feature) {
    final spaced = feature.name.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    );
    return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }
}
