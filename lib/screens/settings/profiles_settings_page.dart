import 'package:flutter/material.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../widgets/profiles/profile_avatar_view.dart';
import '../profiles/edit_profile_screen.dart';
import '../profiles/profile_wall_screen.dart';
import '../profiles/manage_profiles_screen.dart';

/// Settings → Profiles: the roster, and almost nothing else.
///
/// Deliberately thin — everything about one person (avatar, PIN, role, access)
/// lives in that person's profile via Edit, and destructive management
/// (delete, Top Shelf, diagnostics) stays on [ManageProfilesScreen]. This page
/// must not grow a row when a feature does.
///
/// Only reachable in committed-profile mode: the row that opens it is gated on
/// `ProfileRuntime.mode == profileCommitted`.
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
      final registry = ProfileBootstrap.registry;
      final profiles = await registry.listProfiles();
      final activeId = ProfileRuntime.capture().profileId;
      final authorization = await ProfileAuthorizationContext.capture(registry);
      UserProfile? actor;
      try {
        actor = await authorization.validate(registry);
      } catch (_) {
        actor = null;
      }
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _active = profiles.where((p) => p.id == activeId).firstOrNull;
        _mayManage =
            actor != null &&
            actor.role == UserProfileRole.admin &&
            actor.allows(ProfileFeature.manageProfiles);
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
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          registry: registry,
          pins: ProfilePinService(registry: registry),
          authorization: authorization,
        ),
      ),
    );
    if (created == true) await _load();
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
                if (_mayManage) ...[
                  ListTile(
                    leading: const Icon(Icons.person_add_alt_rounded),
                    title: const Text('Create a profile'),
                    subtitle: const Text('Admin, Member or Kid'),
                    onTap: _create,
                  ),
                  ListTile(
                    leading: const Icon(Icons.manage_accounts_rounded),
                    title: const Text('Manage profiles'),
                    subtitle: const Text('Delete, Top Shelf and diagnostics'),
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

  Widget _rosterRow(UserProfile profile) => ListTile(
    leading: ClipRRect(
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
    title: Text(profile.name),
    subtitle: Text(
      '${_roleLabel(profile.role)}${profile.hasPin ? ' · PIN' : ''}',
    ),
    trailing: _mayManage ? const Icon(Icons.chevron_right_rounded) : null,
    onTap: _mayManage ? () => _edit(profile) : null,
  );

  static String _roleLabel(UserProfileRole role) => switch (role) {
    UserProfileRole.admin => 'Admin',
    UserProfileRole.member => 'Member',
    UserProfileRole.child => 'Kid',
  };
}
