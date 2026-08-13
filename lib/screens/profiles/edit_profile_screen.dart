import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../models/profiles/connection_resource.dart';
import '../../services/profiles/connection_resource_service.dart';
import '../../services/profiles/device_key_provider.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_registry.dart';
import '../../services/profiles/profile_creation_service.dart';
import '../../widgets/tv_text_field.dart';

class EditProfileScreen extends StatefulWidget {
  final ProfileRegistry registry;
  final ProfilePinService pins;
  final ProfileAuthorizationContext authorization;
  final UserProfile? profile;

  const EditProfileScreen({
    super.key,
    required this.registry,
    required this.pins,
    required this.authorization,
    this.profile,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  final TextEditingController _pin = TextEditingController();
  late UserProfileRole _role;
  late Set<ProfileFeature> _features;
  bool _saving = false;
  bool _copyDefaults = true;
  late bool _lockOnResume;
  late int _inactivityMinutes;
  late String _avatarKey;
  List<ConnectionResource>? _resources;
  final Set<String> _selectedResources = <String>{};
  final Map<String, Set<ResourcePermission>> _resourcePermissions =
      <String, Set<ResourcePermission>>{};
  late ProfileAuthorizationContext _authorization = widget.authorization;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _name = TextEditingController(text: profile?.name ?? '');
    _role = profile?.role ?? UserProfileRole.member;
    _features = Set<ProfileFeature>.from(
      profile?.policy.enabled ?? ProfilePolicy.defaultsFor(_role).enabled,
    );
    _lockOnResume = profile?.lockOnResume ?? false;
    _inactivityMinutes = profile?.inactivityTimeoutMinutes ?? 0;
    _avatarKey =
        profile?.avatarKey ??
        (profile?.role == UserProfileRole.child ? 'child' : 'person');
    _loadResources();
  }

  Future<void> _loadResources() async {
    final actor = await _authorization.validate(widget.registry);
    final resources = await widget.registry.listGrantedResources(actor.id);
    final targetId = widget.profile?.id;
    _selectedResources.clear();
    _resourcePermissions.clear();
    if (targetId != null) {
      for (final resource in resources) {
        final grant = await widget.registry.getGrant(targetId, resource.id);
        if (grant != null) {
          _selectedResources.add(resource.id);
          _resourcePermissions[resource.id] = {
            for (final permission in ResourcePermission.values)
              if (grant.allows(permission)) permission,
          }..add(ResourcePermission.use);
        }
      }
    }
    if (mounted) setState(() => _resources = resources);
  }

  Future<void> _transferOwnership(ConnectionResource resource) async {
    final target = widget.profile;
    if (target == null || target.id == resource.ownerProfileId) return;
    final operationActor = _authorization;
    await _validateManagingAdmin(operationActor);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer connection ownership?'),
        content: Text(
          '${target.name} will become the owner of ${resource.label}. '
          'Existing profiles keep their current grants, and the previous '
          'owner becomes a borrower.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _validateManagingAdmin(operationActor);
      await ConnectionResourceService(
        registry: widget.registry,
        cipher: DeviceKeyProvider.cipher,
      ).transferOwnership(
        actor: operationActor,
        resourceId: resource.id,
        newOwnerProfileId: target.id,
      );
      _authorization = await _refreshSameManagingAdmin(
        operationActor.profileId,
      );
      await _loadResources();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection ownership transferred')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection could not be transferred')),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _pin
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _setRole(UserProfileRole role) {
    setState(() {
      _role = role;
      _features = Set<ProfileFeature>.from(
        ProfilePolicy.defaultsFor(role).enabled,
      );
    });
  }

  Future<void> _save() async {
    if (_saving || _name.text.trim().isEmpty) return;
    if (_pin.text.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(_pin.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN must contain 4–8 digits')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      var operationActor = _authorization;
      await _validateManagingAdmin(operationActor);
      final policy = ProfilePolicy(enabled: _features);
      final existing = widget.profile;
      late final String savedProfileId;
      if (existing == null) {
        final staged = await ProfileCreationService(widget.registry)
            .createStaged(
              actor: operationActor,
              name: _name.text,
              role: _role,
              policy: policy,
              copyDefaultsFromActive: _copyDefaults,
              avatarKey: _avatarKey,
            );
        savedProfileId = staged.id;
        try {
          if (_pin.text.isNotEmpty) {
            await widget.pins.setPinAsAdmin(
              actor: operationActor,
              targetProfileId: staged.id,
              pin: _pin.text,
            );
          }
          await widget.registry.updateProfile(
            id: staged.id,
            avatarKey: _avatarKey,
            lockOnResume: _lockOnResume,
            inactivityTimeoutMinutes: _inactivityMinutes == 0
                ? null
                : _inactivityMinutes,
            clearInactivityTimeout: _inactivityMinutes == 0,
            actingProfileId: operationActor.profileId,
            actingAuthorizationRevision: operationActor.authorizationRevision,
            actingSessionEpoch: operationActor.sessionEpoch,
          );
          operationActor = await _refreshSameManagingAdmin(
            operationActor.profileId,
          );
          operationActor = await _applyResourceGrants(
            staged.id,
            _role,
            operationActor,
          );
          // Visibility is the last step: a failed PIN/policy/grant write cannot
          // expose a partially configured profile in the picker.
          await widget.registry.completeProfileSetup(
            staged.id,
            actingProfileId: operationActor.profileId,
            actingAuthorizationRevision: operationActor.authorizationRevision,
            actingSessionEpoch: operationActor.sessionEpoch,
          );
        } catch (_) {
          await widget.registry.deleteProfile(staged.id);
          rethrow;
        }
      } else {
        savedProfileId = existing.id;
        await widget.registry.updateProfile(
          id: existing.id,
          name: _name.text,
          avatarKey: _avatarKey,
          role: _role,
          policy: policy,
          lockOnResume: _lockOnResume,
          inactivityTimeoutMinutes: _inactivityMinutes == 0
              ? null
              : _inactivityMinutes,
          clearInactivityTimeout: _inactivityMinutes == 0,
          actingProfileId: operationActor.profileId,
          actingAuthorizationRevision: operationActor.authorizationRevision,
          actingSessionEpoch: operationActor.sessionEpoch,
        );
        operationActor = await _refreshSameManagingAdmin(
          operationActor.profileId,
        );
        if (_pin.text.isNotEmpty) {
          await widget.pins.setPinAsAdmin(
            actor: operationActor,
            targetProfileId: existing.id,
            pin: _pin.text,
          );
          operationActor = await _refreshSameManagingAdmin(
            operationActor.profileId,
          );
        }
        operationActor = await _applyResourceGrants(
          savedProfileId,
          _role,
          operationActor,
        );
      }
      _authorization = operationActor;
      _pin.clear();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this profile')),
      );
    }
  }

  Future<ProfileAuthorizationContext> _applyResourceGrants(
    String targetProfileId,
    UserProfileRole targetRole,
    ProfileAuthorizationContext operationActor,
  ) async {
    final resources = _resources ?? const <ConnectionResource>[];
    final service = ConnectionResourceService(
      registry: widget.registry,
      cipher: DeviceKeyProvider.cipher,
    );
    for (final resource in resources) {
      final existing = await widget.registry.getGrant(
        targetProfileId,
        resource.id,
      );
      final selected = _selectedResources.contains(resource.id);
      final desired =
          _resourcePermissions[resource.id] ??
          _defaultResourcePermissions(targetRole);
      final desiredMask = desired.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      );
      if (selected &&
          (existing == null || existing.permissions != desiredMask)) {
        await service.grant(
          actor: operationActor,
          targetProfileId: targetProfileId,
          resourceId: resource.id,
          permissions: desired,
        );
        operationActor = await _refreshSameManagingAdmin(
          operationActor.profileId,
        );
      } else if (!selected &&
          existing != null &&
          resource.ownerProfileId != targetProfileId) {
        await service.revokeGrant(
          actor: operationActor,
          targetProfileId: targetProfileId,
          resourceId: resource.id,
        );
        operationActor = await _refreshSameManagingAdmin(
          operationActor.profileId,
        );
      }
    }
    return operationActor;
  }

  Set<ResourcePermission> _defaultResourcePermissions(UserProfileRole role) =>
      <ResourcePermission>{
        ResourcePermission.use,
        if (_features.contains(ProfileFeature.downloads) ||
            _features.contains(ProfileFeature.recordings))
          ResourcePermission.download,
        if (role != UserProfileRole.child &&
            _features.contains(ProfileFeature.remoteTransfer))
          ResourcePermission.writeRemote,
      };

  bool _permissionAllowedForRole(ResourcePermission permission) =>
      _role != UserProfileRole.child ||
      permission == ResourcePermission.use ||
      permission == ResourcePermission.download;

  Future<void> _validateManagingAdmin(
    ProfileAuthorizationContext context,
  ) async {
    final actor = await context.validate(widget.registry);
    if (actor.role != UserProfileRole.admin ||
        !actor.allows(ProfileFeature.manageProfiles)) {
      throw StateError('Profile management is not authorized');
    }
  }

  Future<ProfileAuthorizationContext> _refreshSameManagingAdmin(
    String initiatingProfileId,
  ) async {
    final refreshed = await ProfileAuthorizationContext.capture(
      widget.registry,
    );
    if (refreshed.profileId != initiatingProfileId) {
      throw StateError('Managing profile session changed');
    }
    await _validateManagingAdmin(refreshed);
    return refreshed;
  }

  @override
  Widget build(BuildContext context) {
    final editableFeatures = ProfileFeature.values.where(
      (feature) =>
          feature != ProfileFeature.manageProfiles ||
          _role == UserProfileRole.admin,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'Create profile' : 'Edit profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TvTextField(
            controller: _name,
            autofocus: true,
            inputFormatters: <TextInputFormatter>[
              LengthLimitingTextInputFormatter(40),
            ],
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          Text('Avatar', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
                const <String>[
                      'person',
                      'child',
                      'movie',
                      'rocket',
                      'sports',
                      'music',
                    ]
                    .map((key) {
                      return ChoiceChip(
                        selected: _avatarKey == key,
                        avatar: Icon(_avatarIcon(key), size: 18),
                        label: Text(key),
                        onSelected: (_) => setState(() => _avatarKey = key),
                      );
                    })
                    .toList(growable: false),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<UserProfileRole>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: UserProfileRole.values
                .map(
                  (role) =>
                      DropdownMenuItem(value: role, child: Text(role.name)),
                )
                .toList(),
            onChanged: (role) {
              if (role != null) _setRole(role);
            },
          ),
          const SizedBox(height: 12),
          if (widget.profile == null)
            SwitchListTile(
              value: _copyDefaults,
              title: const Text('Copy appearance and playback defaults'),
              subtitle: const Text(
                'Does not copy accounts, history, downloads, paths, or IDs.',
              ),
              onChanged: (value) => setState(() => _copyDefaults = value),
            ),
          TvTextField(
            controller: _pin,
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
                onPressed: _saving
                    ? null
                    : () async {
                        try {
                          final operationActor = _authorization;
                          await _validateManagingAdmin(operationActor);
                          await widget.pins.removePinAsAdmin(
                            actor: operationActor,
                            targetProfileId: widget.profile!.id,
                          );
                          _authorization = await _refreshSameManagingAdmin(
                            operationActor.profileId,
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('PIN protection removed'),
                            ),
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('PIN protection was not changed'),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Admin reset: remove PIN'),
              ),
            ),
          SwitchListTile(
            value: _lockOnResume,
            title: const Text('Lock when the app resumes'),
            onChanged: (value) => setState(() => _lockOnResume = value),
          ),
          DropdownButtonFormField<int>(
            initialValue: _inactivityMinutes,
            decoration: const InputDecoration(labelText: 'Auto-lock'),
            items: const <DropdownMenuItem<int>>[
              DropdownMenuItem(value: 0, child: Text('Never')),
              DropdownMenuItem(value: 5, child: Text('After 5 minutes')),
              DropdownMenuItem(value: 15, child: Text('After 15 minutes')),
              DropdownMenuItem(value: 30, child: Text('After 30 minutes')),
              DropdownMenuItem(value: 60, child: Text('After 1 hour')),
            ],
            onChanged: (value) =>
                setState(() => _inactivityMinutes = value ?? 0),
          ),
          const SizedBox(height: 20),
          Text('Features', style: Theme.of(context).textTheme.titleMedium),
          for (final feature in editableFeatures)
            CheckboxListTile(
              value:
                  _features.contains(feature) &&
                  ProfilePolicy(enabled: _features).allows(_role, feature),
              title: Text(_featureLabel(feature)),
              onChanged: (enabled) {
                setState(() {
                  if (enabled == true) {
                    _features.add(feature);
                  } else {
                    _features.remove(feature);
                  }
                });
              },
            ),
          if (_resources?.isNotEmpty == true) ...[
            const SizedBox(height: 20),
            Text(
              'Shared connections',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'Choose which of your connections this profile may use. Tracker and cloud access can modify the upstream account.',
            ),
            for (final resource in _resources!) ...[
              CheckboxListTile(
                value: _selectedResources.contains(resource.id),
                title: Text(resource.label),
                subtitle: Text(resource.type.name),
                secondary:
                    widget.profile != null &&
                        resource.ownerProfileId != widget.profile!.id &&
                        _role != UserProfileRole.child &&
                        _features.contains(ProfileFeature.manageConnections)
                    ? IconButton(
                        tooltip: 'Transfer ownership to this profile',
                        onPressed: () => _transferOwnership(resource),
                        icon: const Icon(Icons.swap_horiz_rounded),
                      )
                    : const Icon(Icons.key_rounded),
                onChanged: resource.ownerProfileId == widget.profile?.id
                    ? null
                    : (selected) => setState(() {
                        if (selected == true) {
                          _selectedResources.add(resource.id);
                          _resourcePermissions.putIfAbsent(
                            resource.id,
                            () => _defaultResourcePermissions(_role),
                          );
                        } else {
                          _selectedResources.remove(resource.id);
                        }
                      }),
              ),
              if (_selectedResources.contains(resource.id) &&
                  resource.ownerProfileId != widget.profile?.id)
                Padding(
                  padding: const EdgeInsets.only(
                    left: 24,
                    right: 12,
                    bottom: 8,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final permission in ResourcePermission.values)
                        if (_permissionAllowedForRole(permission))
                          FilterChip(
                            label: Text(_permissionLabel(permission)),
                            selected:
                                (_resourcePermissions[resource.id] ??
                                        _defaultResourcePermissions(_role))
                                    .contains(permission),
                            onSelected: permission == ResourcePermission.use
                                ? null
                                : (selected) => setState(() {
                                    final permissions = _resourcePermissions
                                        .putIfAbsent(
                                          resource.id,
                                          () => _defaultResourcePermissions(
                                            _role,
                                          ),
                                        );
                                    if (selected) {
                                      permissions.add(permission);
                                    } else {
                                      permissions.remove(permission);
                                    }
                                  }),
                          ),
                    ],
                  ),
                ),
            ],
          ],
        ],
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

  static String _permissionLabel(ResourcePermission permission) =>
      switch (permission) {
        ResourcePermission.use => 'Use',
        ResourcePermission.download => 'Download / record',
        ResourcePermission.writeRemote => 'Send remotely',
        ResourcePermission.manage => 'Manage',
        ResourcePermission.revealSecret => 'Reveal secret',
        ResourcePermission.share => 'Share onward',
      };

  static IconData _avatarIcon(String key) => switch (key) {
    'child' => Icons.child_care_rounded,
    'movie' => Icons.movie_filter_rounded,
    'rocket' => Icons.rocket_launch_rounded,
    'sports' => Icons.sports_esports_rounded,
    'music' => Icons.headphones_rounded,
    _ => Icons.person_rounded,
  };
}
