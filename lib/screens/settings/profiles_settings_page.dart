import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/profiles/profile_diagnostics_service.dart';
import '../../theme/app_focus.dart';
import '../../theme/app_theme_scope.dart';
import '../../theme/widgets/parallax_focus.dart';
import '../../utils/platform_util.dart';
import '../../widgets/profiles/profile_avatar_view.dart';
import '../../widgets/remote/remote_control_screen.dart';
import '../profiles/edit_profile_screen.dart';
import '../profiles/profile_wall_screen.dart';
import '../profiles/profile_row_actions.dart';
import '../profiles/profile_setup_flow.dart';
import 'widgets/settings_widgets.dart';

/// Settings → Profiles: the household hub.
///
/// The signed-in identity, other people, device behaviour and household
/// actions are intentionally separate. Backup/restore lives under Data &
/// Backup; picker presentation and Apple TV Top Shelf live under Appearance.
///
/// Only reachable in committed-profile mode: the row that opens it is gated
/// on `ProfileRuntime.mode == profileCommitted`.
class ProfilesSettingsPage extends StatefulWidget {
  const ProfilesSettingsPage({super.key});

  @override
  State<ProfilesSettingsPage> createState() => _ProfilesSettingsPageState();
}

class _ProfilesSettingsPageState extends State<ProfilesSettingsPage> {
  List<UserProfile>? _profiles;
  UserProfile? _active;
  bool _mayManage = false;
  bool _loading = true;
  final FocusNode _firstActionFocus = FocusNode(
    debugLabel: 'profiles-switch-profile',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstActionFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await ProfileGateAlwaysAsk.warm();
      final registry = ProfileBootstrap.registry;
      final activeId = ProfileRuntime.capture().profileId;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      UserProfile? actor;
      try {
        actor = await authorization.validate(registry);
      } catch (_) {
        actor = null;
      }
      final mayManage =
          actor != null &&
          actor.role == UserProfileRole.admin &&
          actor.allows(ProfileFeature.manageProfiles);
      // Managers see the whole household, disabled profiles included —
      // hiding them is how "why can't I delete it" support threads start.
      final profiles = await registry.listProfiles(includeDisabled: mayManage);
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _active = profiles.where((p) => p.id == activeId).firstOrNull;
        _mayManage = mayManage;
        _loading = false;
      });
      if (PlatformUtil.isTelevision) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary is! FocusScopeNode) return;
          _firstActionFocus.requestFocus();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profiles = const <UserProfile>[];
        _loading = false;
      });
    }
  }

  void _switchProfile() {
    // The gate owns switching (lock, lease revoke, session teardown); this
    // page only asks it to take over.
    Navigator.of(context).popUntil((route) => route.isFirst);
    MainPageBridge.showProfilePicker?.call();
  }

  Future<void> _edit(UserProfile profile) async {
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    if (!mounted) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          registry: registry,
          pins: ProfilePinService(registry: registry),
          authorization: authorization,
          profile: profile,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _create() async {
    // The questionnaire is the create path now: role presets, five human
    // questions, and it writes an explicit policy — the raw editor stays
    // the deep-identity tool (PIN, photo avatars), reachable from Review.
    final created = await ProfileSetupFlow.show(context);
    if (created) await _load();
  }

  /// ONE panel per profile — the hub's whole point. DPAD-safe by
  /// construction: plain focusable ListTiles in a dialog, first one
  /// autofocused, nothing trailing inside a focused row's rect.
  Future<void> _profileActions(UserProfile profile) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(profile.name),
        children: [
          ListTile(
            autofocus: true,
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Edit'),
            subtitle: const Text('Name, avatar, PIN, access'),
            onTap: () => Navigator.of(dialogContext).pop('edit'),
          ),
          if (profile.isEnabled)
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Switch to this profile'),
              onTap: () => Navigator.of(dialogContext).pop('switch'),
            ),
          ListTile(
            leading: Icon(
              profile.isEnabled
                  ? Icons.pause_circle_outline_rounded
                  : Icons.play_circle_outline_rounded,
            ),
            title: Text(
              profile.isEnabled ? 'Disable profile' : 'Enable profile',
            ),
            onTap: () => Navigator.of(dialogContext).pop('toggle'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Delete profile'),
            textColor: Theme.of(context).colorScheme.error,
            iconColor: Theme.of(context).colorScheme.error,
            onTap: () => Navigator.of(dialogContext).pop('delete'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _edit(profile);
      case 'switch':
        Navigator.of(context).popUntil((route) => route.isFirst);
        MainPageBridge.switchProfile?.call(profile.id);
      case 'toggle':
      case 'delete':
        final registry = ProfileBootstrap.registry;
        final authorization = await ProfileAuthorizationContext.capture(
          registry,
        );
        if (!mounted) return;
        final actions = ProfileRowActions(
          context: context,
          registry: registry,
          authorization: authorization,
        );
        final changed = action == 'toggle'
            ? await actions.toggleEnabled(profile)
            : await actions.delete(profile);
        if (changed) await _load();
    }
  }

  Future<void> _sendToTv() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RemoteControlScreen()),
    );
  }

  Future<void> _showDiagnostics() async {
    final report = await ProfileDiagnosticsService.collectJson(
      ProfileBootstrap.registry,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profile diagnostics'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles ?? const <UserProfile>[];
    return SettingsPageScaffold(
      title: 'Profiles',
      actions: _mayManage
          ? [
              PopupMenuButton<String>(
                tooltip: 'More profile options',
                onSelected: (value) {
                  if (value == 'diagnostics') _showDiagnostics();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'diagnostics',
                    child: ListTile(
                      leading: Icon(Icons.health_and_safety_outlined),
                      title: Text('Profile diagnostics'),
                    ),
                  ),
                ],
              ),
            ]
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SettingsPageHeader(
                        icon: Icons.people_alt_rounded,
                        title: 'Profiles',
                        subtitle:
                            'People, access and this device\'s sign-in behavior',
                      ),
                      const SizedBox(height: 24),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 860;
                          final left = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_active != null)
                                _currentProfileSection(_active!),
                              if (_mayManage ||
                                  profiles.any(
                                    (profile) => profile.id != _active?.id,
                                  )) ...[
                                const SizedBox(height: 18),
                                _otherProfilesSection(profiles),
                              ],
                            ],
                          );
                          final right = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _behaviorSection(),
                              if (_mayManage) ...[
                                const SizedBox(height: 18),
                                _householdSection(),
                              ],
                            ],
                          );
                          if (!wide) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                left,
                                const SizedBox(height: 18),
                                right,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: left),
                              const SizedBox(width: 18),
                              Expanded(child: right),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _currentProfileSection(UserProfile active) => SettingsSection(
    title: 'Current profile',
    children: [
      _CurrentProfileIdentity(profile: active),
      SettingsTile(
        key: const ValueKey('profiles-switch'),
        focusNode: _firstActionFocus,
        icon: Icons.swap_horiz_rounded,
        title: 'Switch profile',
        subtitle: 'Choose who is watching now',
        onTap: () async => _switchProfile(),
      ),
      if (_mayManage)
        SettingsTile(
          key: const ValueKey('profiles-edit-current'),
          icon: Icons.edit_rounded,
          title: 'Edit profile',
          subtitle: 'Name, avatar, PIN and access',
          onTap: () => _edit(active),
        ),
    ],
  );

  Widget _otherProfilesSection(List<UserProfile> profiles) {
    final others = profiles
        .where((profile) => profile.id != _active?.id)
        .toList(growable: false);
    return SettingsSection(
      title: 'Other profiles',
      children: [
        for (final profile in others)
          _ProfileRosterTile(
            profile: profile,
            subtitle: [
              _roleLabel(profile.role),
              if (profile.hasPin) 'PIN',
              if (!profile.isEnabled) 'disabled',
            ].join(' · '),
            onTap: () async {
              if (_mayManage) {
                await _profileActions(profile);
              } else {
                Navigator.of(context).popUntil((route) => route.isFirst);
                MainPageBridge.switchProfile?.call(profile.id);
              }
            },
          ),
        if (_mayManage)
          SettingsTile(
            key: const ValueKey('profiles-create'),
            icon: Icons.person_add_alt_rounded,
            title: 'Create a profile',
            subtitle: 'Admin, Member or Kid',
            onTap: _create,
          ),
      ],
    );
  }

  Widget _behaviorSection() => SettingsSection(
    title: 'Profile behavior',
    children: [
      SettingsToggleTile(
        key: const ValueKey('profiles-always-ask'),
        icon: Icons.login_rounded,
        title: 'Ask who\'s watching at startup',
        subtitle: 'Show the profile picker when Debrify opens',
        value: ProfileGateAlwaysAsk.cached,
        onChanged: (value) async {
          await ProfileGateAlwaysAsk.set(value);
          if (mounted) setState(() {});
        },
      ),
    ],
  );

  Widget _householdSection() => SettingsSection(
    title: 'Household',
    children: [
      SettingsTile(
        key: const ValueKey('profiles-send-tv'),
        icon: Icons.cast_rounded,
        title: 'Send profiles to TV',
        subtitle: 'Profiles, connections and PINs',
        onTap: _sendToTv,
      ),
    ],
  );

  static String _roleLabel(UserProfileRole role) => switch (role) {
    UserProfileRole.admin => 'Admin',
    UserProfileRole.member => 'Member',
    UserProfileRole.child => 'Kid',
  };
}

class _CurrentProfileIdentity extends StatelessWidget {
  const _CurrentProfileIdentity({required this.profile});
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 58,
            child: ClipRRect(
              borderRadius: app.shape.br(14),
              child: ProfileAvatarView(
                profileId: profile.id,
                avatarKey: profile.avatarKey,
                role: profile.role,
                name: profile.name,
                animateWhenIdle: !PlatformUtil.isTelevision,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_ProfilesRole.label(profile.role)} · Signed in'
                  '${profile.hasPin ? ' · PIN' : ''}',
                  style: TextStyle(fontSize: 12, color: t.dim),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: t.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Active',
              style: TextStyle(
                color: t.success,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfilesRole {
  static String label(UserProfileRole role) => switch (role) {
    UserProfileRole.admin => 'Admin',
    UserProfileRole.member => 'Member',
    UserProfileRole.child => 'Kid',
  };
}

/// A profile row is one focus target on every platform. The avatar, text and
/// chevron are presentation only, so TV never has to discover a tiny trailing
/// menu inside the row's focus rectangle.
class _ProfileRosterTile extends StatefulWidget {
  const _ProfileRosterTile({
    required this.profile,
    required this.subtitle,
    required this.onTap,
  });

  final UserProfile profile;
  final String subtitle;
  final Future<void> Function() onTap;

  @override
  State<_ProfileRosterTile> createState() => _ProfileRosterTileState();
}

class _ProfileRosterTileState extends State<_ProfileRosterTile> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'profile-roster-row');
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    final spotlight = app.id == 'spotlight';
    final lit = _focusNode.hasFocus || _hovered;
    final inverse =
        spotlight && lit && app.focus.expression == FocusExpression.parallax;
    final foreground = inverse ? app.inkOn(app.core.tx) : app.core.tx;
    final radius = app.shape.br(12);
    return ParallaxFocus(
      focused: _focusNode.hasFocus,
      shape: ParallaxShape.settingsRow,
      radius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: inverse ? app.core.tx : (lit ? t.panel2 : Colors.transparent),
          borderRadius: radius,
          border: Border.all(
            color: inverse
                ? app.core.tx
                : (_focusNode.hasFocus ? t.accent : Colors.transparent),
          ),
        ),
        child: InkWell(
          focusNode: _focusNode,
          onFocusChange: (_) => setState(() {}),
          onHover: (value) => setState(() => _hovered = value),
          onTap: () async => widget.onTap(),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Opacity(
                  opacity: widget.profile.isEnabled ? 1 : 0.45,
                  child: SizedBox.square(
                    dimension: 40,
                    child: ClipRRect(
                      borderRadius: app.shape.br(10),
                      child: ProfileAvatarView(
                        profileId: widget.profile.id,
                        avatarKey: widget.profile.avatarKey,
                        role: widget.profile.role,
                        name: widget.profile.name,
                        focused: _focusNode.hasFocus,
                        animateWhenIdle: !PlatformUtil.isTelevision,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: inverse
                              ? foreground.withValues(alpha: 0.5)
                              : t.dim,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: inverse ? foreground.withValues(alpha: 0.42) : t.dim2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
