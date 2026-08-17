import 'package:flutter/material.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../widgets/profiles/profile_avatar_view.dart';
import '../../widgets/remote/remote_control_screen.dart';
import '../profiles/edit_profile_screen.dart';
import '../profiles/profile_wall_screen.dart';
import '../profiles/manage_profiles_screen.dart';
import '../profiles/profile_row_actions.dart';
import '../profiles/profile_setup_flow.dart';
import 'profile_backup_flows.dart';

/// Settings → Profiles: the household hub.
///
/// One level shows everything (the roster with role/PIN/disabled state and
/// the household actions — create, send to TV, back up, restore); selecting
/// a profile opens ONE action panel (edit, enable/disable, delete — the
/// same flows [ManageProfilesScreen] runs, via [ProfileRowActions]).
/// [ManageProfilesScreen] remains for the long-tail (Top Shelf,
/// diagnostics). This page must not grow a row when a feature does —
/// per-profile things belong in the action panel, not the hub.
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

  @override
  void initState() {
    super.initState();
    _load();
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
      final profiles = await registry.listProfiles(
        includeDisabled: mayManage,
      );
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _active = profiles.where((p) => p.id == activeId).firstOrNull;
        _mayManage = mayManage;
        _loading = false;
      });
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

  Future<void> _manage() async {
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ManageProfilesScreen(
          registry: registry,
          authorization: authorization,
        ),
      ),
    );
    await _load();
  }

  /// ONE panel per profile — the hub's whole point. DPAD-safe by
  /// construction: plain focusable ListTiles in a dialog, first one
  /// autofocused, nothing trailing inside a focused row's rect.
  Future<void> _profileActions(UserProfile profile) async {
    final isActive = profile.id == _active?.id;
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
          if (isActive)
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('Switch profile'),
              onTap: () => Navigator.of(dialogContext).pop('switch'),
            ),
          // The registry hard-blocks disabling or deleting the profile you
          // are signed into — offering them here would only produce a
          // generic failure snackbar. Switch away first; the actions appear
          // on the row once it is no longer "you".
          if (!isActive) ...[
            ListTile(
              leading: Icon(
                profile.isEnabled
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
              ),
              title: Text(profile.isEnabled ? 'Disable' : 'Enable'),
              onTap: () => Navigator.of(dialogContext).pop('toggle'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () => Navigator.of(dialogContext).pop('delete'),
            ),
          ],
        ],
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'edit':
        await _edit(profile);
      case 'switch':
        _switchProfile();
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

  Future<void> _backUp() async {
    await ProfileBackupFlows(context).createProfileBackup();
  }

  Future<void> _restore() async {
    await ProfileBackupFlows(context, onRestored: _load).restoreProfileBackup();
  }

  Future<void> _sendToTv() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RemoteControlScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles ?? const <UserProfile>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Profiles')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_active != null) _activeCard(_active!),
                const SizedBox(height: 20),
                Text(
                  'ON THIS DEVICE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.8,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final profile in profiles) _rosterRow(profile),
                ListTile(
                  leading: const Icon(Icons.style_rounded),
                  title: const Text('Who\'s-watching style'),
                  subtitle: Text(
                    ProfileGateStyle.cached == ProfileGateStyle.wall
                        ? 'Portrait Wall'
                        : 'Classic',
                  ),
                  onTap: () async {
                    await ProfileGateStyle.set(
                      ProfileGateStyle.cached == ProfileGateStyle.wall
                          ? ProfileGateStyle.classic
                          : ProfileGateStyle.wall,
                    );
                    if (mounted) setState(() {});
                  },
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.login_rounded),
                  title: const Text('Ask who\'s watching at startup'),
                  subtitle: Text(
                    ProfileGateAlwaysAsk.cached
                        ? 'Always — even with a single profile'
                        : 'A sole profile without a PIN signs in on its own',
                  ),
                  value: ProfileGateAlwaysAsk.cached,
                  onChanged: (value) async {
                    await ProfileGateAlwaysAsk.set(value);
                    if (mounted) setState(() {});
                  },
                ),
                if (_mayManage) ...[
                  const SizedBox(height: 16),
                  Text(
                    'HOUSEHOLD',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.8,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    leading: const Icon(Icons.person_add_alt_rounded),
                    title: const Text('Create a profile'),
                    subtitle: const Text('Admin, Member or Kid'),
                    onTap: _create,
                  ),
                  ListTile(
                    leading: const Icon(Icons.cast_rounded),
                    title: const Text('Send everything to TV'),
                    subtitle: const Text(
                      'All profiles, connections and PINs over Remote',
                    ),
                    onTap: _sendToTv,
                  ),
                  ListTile(
                    leading: const Icon(Icons.save_alt_rounded),
                    title: const Text('Back up'),
                    subtitle: const Text('Encrypted file — one or all profiles'),
                    onTap: _backUp,
                  ),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore_rounded),
                    title: const Text('Restore'),
                    subtitle: const Text('From a Debrify backup file'),
                    onTap: _restore,
                  ),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_rounded),
                    title: const Text('More management'),
                    subtitle: const Text('Top Shelf and diagnostics'),
                    onTap: _manage,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _activeCard(UserProfile active) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colors.primaryContainer.withValues(alpha: .35),
        border: Border.all(color: colors.primary.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 56,
              height: 56,
              child: ProfileAvatarView(
                profileId: active.id,
                avatarKey: active.avatarKey,
                role: active.role,
                name: active.name,
                focused: true,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_roleLabel(active.role)} · signed in'
                  '${active.hasPin ? ' · PIN' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (_mayManage)
            IconButton(
              tooltip: 'Edit',
              autofocus: true,
              onPressed: () => _edit(active),
              icon: const Icon(Icons.edit_rounded),
            ),
          FilledButton.tonal(
            autofocus: !_mayManage,
            onPressed: _switchProfile,
            child: const Text('Switch'),
          ),
        ],
      ),
    );
  }

  Widget _rosterRow(UserProfile profile) {
    final isActive = profile.id == _active?.id;
    return ListTile(
      // Not `enabled: _mayManage` — that would grey the whole roster for
      // non-managers, who deserve a readable view-only list. A null onTap
      // already makes rows inert (and unfocusable) for them.
      leading: Opacity(
        opacity: profile.isEnabled ? 1 : 0.45,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 40,
            height: 40,
            child: ProfileAvatarView(
              profileId: profile.id,
              avatarKey: profile.avatarKey,
              role: profile.role,
              name: profile.name,
            ),
          ),
        ),
      ),
      title: Text(profile.name),
      subtitle: Text(
        [
          _roleLabel(profile.role),
          if (isActive) 'you',
          if (profile.hasPin) 'PIN',
          if (!profile.isEnabled) 'disabled',
        ].join(' · '),
      ),
      trailing: _mayManage ? const Icon(Icons.more_horiz_rounded) : null,
      onTap: _mayManage ? () => _profileActions(profile) : null,
    );
  }

  static String _roleLabel(UserProfileRole role) => switch (role) {
    UserProfileRole.admin => 'Admin',
    UserProfileRole.member => 'Member',
    UserProfileRole.child => 'Kid',
  };
}
