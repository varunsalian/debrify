import '../../services/webdav_sync/webdav_sync_save_feedback.dart';
import '../../widgets/webdav_sync/webdav_save_status.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/user_profile.dart';
import '../../models/profiles/connection_resource.dart';
import '../../services/profiles/connection_resource_service.dart';
import '../../services/profiles/device_key_provider.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_avatar_ingest.dart';
import '../../services/profiles/profile_avatar_mutation.dart';
import '../../services/profiles/profile_avatar_policy.dart';
import '../../services/profiles/profile_diagnostics_service.dart';
import '../../services/profiles/profile_engine_assignment_service.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_registry.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_creation_service.dart';
import '../../utils/platform_util.dart';
import '../../widgets/profiles/profile_art.dart';
import '../../widgets/profiles/profile_avatar_view.dart';
import '../../widgets/tv_text_field.dart';

enum _TvProfileSection { profile, pages, access, lock, data }

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

class _EnsureVisibleOnFocus extends StatelessWidget {
  const _EnsureVisibleOnFocus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (focused) {
      if (!focused) return;
      Scrollable.ensureVisible(
        context,
        alignment: .35,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    },
    child: child,
  );
}

/// Gives a read-only TV row a real DPAD stop. Flutter removes disabled
/// ListTiles from focus traversal, which used to leave the active Admin's
/// Access page with no way to advance (and therefore no way to scroll).
class _TvReadOnlyScrollAnchor extends StatefulWidget {
  const _TvReadOnlyScrollAnchor({required this.child});

  final Widget child;

  @override
  State<_TvReadOnlyScrollAnchor> createState() =>
      _TvReadOnlyScrollAnchorState();
}

class _TvReadOnlyScrollAnchorState extends State<_TvReadOnlyScrollAnchor> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (focused) {
        if (_focused != focused) setState(() => _focused = focused);
        if (focused) {
          Scrollable.ensureVisible(
            context,
            alignment: .5,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      },
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? colors.primary : Colors.transparent,
            width: 3,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

class _TvActionSurface extends StatefulWidget {
  const _TvActionSurface({
    super.key,
    required this.child,
    required this.onPressed,
    this.selected = false,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChange,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool selected;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<_TvActionSurface> createState() => _TvActionSurfaceState();
}

class _TvActionSurfaceState extends State<_TvActionSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = _focused || widget.selected;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: widget.onKeyEvent,
      child: AnimatedScale(
        scale: _focused ? 1.025 : 1,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: active
                ? colors.primary.withValues(alpha: widget.selected ? .15 : .1)
                : colors.surfaceContainerHighest.withValues(alpha: .55),
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            border: Border.all(
              color: active ? colors.primary : Colors.transparent,
              width: _focused ? 3 : 2,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: .28),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            focusNode: widget.focusNode,
            onFocusChange: (focused) {
              if (_focused != focused) setState(() => _focused = focused);
              widget.onFocusChange?.call(focused);
              if (focused) {
                Scrollable.ensureVisible(
                  context,
                  alignment: .35,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                );
              }
            },
            onTap: widget.onPressed,
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            child: IconTheme.merge(
              data: IconThemeData(color: active ? colors.primary : null),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: active ? colors.primary : null),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TvAutoLockField extends StatefulWidget {
  const _TvAutoLockField({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  State<_TvAutoLockField> createState() => _TvAutoLockFieldState();
}

class _TvAutoLockFieldState extends State<_TvAutoLockField> {
  static const _values = <int>[0, 5, 15, 30, 60];
  bool _focused = false;

  String get _label => switch (widget.value) {
    0 => 'Never',
    5 => 'After 5 minutes',
    15 => 'After 15 minutes',
    30 => 'After 30 minutes',
    60 => 'After 1 hour',
    _ => 'Never',
  };

  void _move(int delta) {
    final current = _values.indexOf(widget.value);
    final next = (current + delta).clamp(0, _values.length - 1);
    if (next != current) widget.onChanged(_values[next]);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _move(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _move(1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? colors.primary : Colors.transparent,
            width: 3,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: .25),
                    blurRadius: 16,
                  ),
                ]
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onFocusChange: (focused) {
            setState(() => _focused = focused);
            if (focused) {
              Scrollable.ensureVisible(
                context,
                alignment: .65,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
              );
            }
          },
          onTap: () => _move(1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-lock',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: _focused ? colors.primary : null,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.chevron_left_rounded, size: 30),
                    Expanded(
                      child: Text(
                        _label,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, size: 30),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Immutable save input. The form is also focus/pointer locked while saving,
/// but the snapshot is the correctness boundary: no value is re-read after an
/// authorization, PIN KDF, grant write, or engine copy yields to the event
/// loop.
class _ProfileEditSnapshot {
  final String name;
  final String pin;
  final UserProfileRole role;
  final Set<ProfileFeature> features;
  final bool copyDefaults;
  final bool lockOnResume;
  final int inactivityMinutes;
  final String avatarKey;
  final Uint8List? pendingAvatarBytes;
  final List<ConnectionResource> resources;
  final Set<String> selectedResources;
  final Map<String, Set<ResourcePermission>> resourcePermissions;
  final Set<String> selectedEngines;

  const _ProfileEditSnapshot({
    required this.name,
    required this.pin,
    required this.role,
    required this.features,
    required this.copyDefaults,
    required this.lockOnResume,
    required this.inactivityMinutes,
    required this.avatarKey,
    required this.pendingAvatarBytes,
    required this.resources,
    required this.selectedResources,
    required this.resourcePermissions,
    required this.selectedEngines,
  });
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
  _TvProfileSection _tvSection = _TvProfileSection.profile;
  // One node per rail section, plus the rail's Save item at the end.
  late final List<FocusNode> _tvTabFocusNodes;

  /// Set on the first Pages toggle — until then a save preserves the stored
  /// policy (edit) or the role defaults (create), same as when no feature
  /// control existed at all.
  bool _policyTouched = false;

  /// True while a rail UP/DOWN move is transferring focus between rail
  /// items. Distinguishes deliberate rail movement from focus ENTERING the
  /// rail from the content pane, where geometric traversal may land on
  /// whichever tab is nearest — not the current section's.
  bool _railMoveInProgress = false;

  // Where downloads/remote started, so their paired features (recordings,
  // remoteTransfer) follow the toggle only when the answer actually MOVED —
  // an untouched save must not re-couple a policy the old feature matrix
  // split (mirrors ProfileSetupFlow._seedDownloads/_seedRemote).
  late bool _seedDownloads;
  late bool _seedRemote;

  /// A picked-but-not-saved image. Held in memory and ingested at save time,
  /// once the target profile's id exists (a created profile has none until
  /// `createStaged`). Nothing touches disk if the user backs out.
  Uint8List? _pendingAvatarBytes;

  List<ConnectionResource>? _resources;
  List<ProfileEngineAssignment>? _engines;
  final Set<String> _selectedResources = <String>{};
  final Set<String> _selectedEngines = <String>{};
  final Map<String, Set<ResourcePermission>> _resourcePermissions =
      <String, Set<ResourcePermission>>{};
  String? _setupLoadError;
  late ProfileAuthorizationContext _authorization = widget.authorization;

  @override
  void initState() {
    super.initState();
    _tvTabFocusNodes = [
      for (final section in _TvProfileSection.values)
        FocusNode(debugLabel: 'Edit profile ${section.name} tab'),
      FocusNode(debugLabel: 'Edit profile save'),
    ];
    final profile = widget.profile;
    _name = TextEditingController(text: profile?.name ?? '');
    _role = profile?.role ?? UserProfileRole.member;
    // Always the policy this screen will WRITE (policyFor: stored policy on
    // edit, role defaults on create) — grant masks derive from _features, so
    // seeding it from the role CEILING would hand every newly ticked
    // resource writeRemote regardless of the profile's remote answer.
    _features = Set<ProfileFeature>.from(
      profile?.policy.enabled ?? ProfilePolicy.defaultsFor(_role).enabled,
    );
    _seedDownloads = _features.contains(ProfileFeature.downloads);
    _seedRemote = _features.contains(ProfileFeature.remoteControl);
    _lockOnResume = profile?.lockOnResume ?? false;
    _inactivityMinutes = profile?.inactivityTimeoutMinutes ?? 0;
    _avatarKey =
        profile?.avatarKey ??
        (profile?.role == UserProfileRole.child ? 'child' : 'person');
    _loadSetupOptions();
  }

  Future<void> _loadSetupOptions() async {
    try {
      final actor = await _authorization.validate(widget.registry);
      final (resources, engines) = widget.setupOptionsLoader != null
          ? await widget.setupOptionsLoader!()
          : (
              await widget.registry.listGrantedResources(actor.id),
              await ProfileEngineAssignmentService(
                widget.registry,
              ).listForTarget(
                actor: _authorization,
                targetProfileId: widget.profile?.id,
              ),
            );
      final selectedResources = <String>{};
      final resourcePermissions = <String, Set<ResourcePermission>>{};
      final targetId = widget.profile?.id;
      if (targetId != null) {
        for (final resource in resources) {
          final grant = await widget.registry.getGrant(targetId, resource.id);
          if (grant != null) {
            selectedResources.add(resource.id);
            resourcePermissions[resource.id] = {
              for (final permission in ResourcePermission.values)
                if (grant.allows(permission)) permission,
            }..add(ResourcePermission.use);
          }
        }
      }
      await _validateManagingAdmin(_authorization);
      if (!mounted) return;
      setState(() {
        _resources = resources;
        _engines = engines;
        _selectedResources
          ..clear()
          ..addAll(selectedResources);
        _resourcePermissions
          ..clear()
          ..addAll(resourcePermissions);
        _selectedEngines
          ..clear()
          ..addAll(
            widget.profile == null
                ? engines.map((engine) => engine.id)
                : engines
                      .where((engine) => engine.assignedToTarget)
                      .map((engine) => engine.id),
          );
        _setupLoadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _setupLoadError = 'Profile options could not be loaded');
    }
  }

  Future<void> _loadResources() async {
    try {
      final actor = await _authorization.validate(widget.registry);
      final resources = await widget.registry.listGrantedResources(actor.id);
      if (!mounted) return;
      setState(() {
        _resources = resources;
        _setupLoadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _setupLoadError = 'Connections could not be reloaded');
    }
  }

  Future<void> _transferOwnership(ConnectionResource resource) async {
    final target = widget.profile;
    if (target == null || target.id == resource.ownerProfileId) return;
    final operationActor = _authorization;
    await _validateManagingAdmin(operationActor);
    if (!mounted) return;
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
    for (final node in _tvTabFocusNodes) {
      node.dispose();
    }
    _name.dispose();
    _pin
      ..clear()
      ..dispose();
    super.dispose();
  }

  void _setRole(UserProfileRole role) {
    if (_saving) return;
    setState(() {
      _role = role;
      // The ProfileSetupFlow rule: a role CHANGE is a re-preset (the new
      // role's defaults), while returning to the stored role restores the
      // stored policy — so what the Pages pane displays is always exactly
      // what a save would write.
      final existing = widget.profile;
      _features = Set<ProfileFeature>.from(
        existing != null && existing.role == role
            ? existing.policy.enabled
            : ProfilePolicy.defaultsFor(role).enabled,
      );
      // The pairs are re-coupled by the reseed above, so the
      // follow-only-when-moved baselines reset too.
      _seedDownloads = _features.contains(ProfileFeature.downloads);
      _seedRemote = _features.contains(ProfileFeature.remoteControl);
    });
  }

  Future<void> _pickAvatarImage() async {
    if (_saving) return;
    try {
      // Android document providers commonly reject custom MIME/extension
      // filters. Pick any file, then trust magic-byte validation below.
      final pick = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose an avatar image or GIF',
        type: FileType.any,
        withData: false,
      );
      if (pick == null || pick.files.isEmpty) return;
      final file = pick.files.single;
      if (file.size > ProfileAvatarIngest.maxInputBytes) {
        throw const ProfileAvatarRejected(
          'That image is too large to open. Choose one under 12 MB.',
        );
      }
      final bytes = await _readPickedBytes(file);
      final prepared = await ProfileAvatarIngest.prepare(bytes);
      if (!mounted || _saving) return;
      setState(() => _pendingAvatarBytes = prepared.bytes);
    } on ProfileAvatarRejected catch (rejected) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(rejected.message)));
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The image picker is not available.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That image could not be opened.')),
      );
    }
  }

  Future<Uint8List> _readPickedBytes(PlatformFile picked) async {
    final inline = picked.bytes;
    if (inline != null) {
      if (inline.length > ProfileAvatarIngest.maxInputBytes) {
        throw const ProfileAvatarRejected(
          'That image is too large to open. Choose one under 12 MB.',
        );
      }
      return inline;
    }
    final path = picked.path;
    if (path == null || path.isEmpty) {
      throw const ProfileAvatarRejected('That file could not be read.');
    }
    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in File(path).openRead()) {
      if (length > ProfileAvatarIngest.maxInputBytes - chunk.length) {
        throw const ProfileAvatarRejected(
          'That image is too large to open. Choose one under 12 MB.',
        );
      }
      builder.add(chunk);
      length += chunk.length;
    }
    return builder.takeBytes();
  }

  /// Shown exactly once, right after a PIN is set: the code exists only in
  /// this dialog — the app stores a hash. Every PIN change mints a new one.
  Future<void> _showRecoveryCode(String profileName, String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Save this recovery code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'If the PIN for $profileName is ever forgotten, this code '
              'removes it from the profile screen. It is shown only this '
              'once — write it down or save it in a password manager.',
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('I saved it'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final syncRevision = WebDavSyncSaveFeedback.instance.revision;
    if (_saving || _name.text.trim().isEmpty) return;
    if (_resources == null || _engines == null || _setupLoadError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_setupLoadError ?? 'Profile options are still loading'),
        ),
      );
      return;
    }
    if (_pin.text.isNotEmpty && !RegExp(r'^\d{4,8}$').hasMatch(_pin.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN must contain 4–8 digits')),
      );
      return;
    }
    // The paired features follow their toggle only when the answer moved
    // from where this session started (the ProfileSetupFlow rule).
    final effectiveFeatures = Set<ProfileFeature>.from(_features);
    void follow(bool moved, bool on, ProfileFeature paired) {
      if (!moved) return;
      on ? effectiveFeatures.add(paired) : effectiveFeatures.remove(paired);
    }

    final downloadsOn = _features.contains(ProfileFeature.downloads);
    final remoteOn = _features.contains(ProfileFeature.remoteControl);
    follow(
      downloadsOn != _seedDownloads,
      downloadsOn,
      ProfileFeature.recordings,
    );
    follow(remoteOn != _seedRemote, remoteOn, ProfileFeature.remoteTransfer);
    // Clamp through the role ceiling BEFORE encoding: decode strips
    // ceiling-denied bits, so a raw set carrying one (e.g. remoteTransfer
    // paired onto a Kid) would never round-trip — and _save's persisted
    // encode comparison would misreport a committed save as failed.
    final ceilingLens = ProfilePolicy(enabled: effectiveFeatures);
    final clampedFeatures = <ProfileFeature>{
      for (final feature in effectiveFeatures)
        if (ceilingLens.allows(_role, feature)) feature,
    };
    final snapshot = _ProfileEditSnapshot(
      name: _name.text,
      pin: _pin.text,
      role: _role,
      features: Set<ProfileFeature>.unmodifiable(clampedFeatures),
      copyDefaults: _copyDefaults,
      lockOnResume: _lockOnResume,
      inactivityMinutes: _inactivityMinutes,
      avatarKey: _avatarKey,
      pendingAvatarBytes: _pendingAvatarBytes,
      resources: List<ConnectionResource>.unmodifiable(_resources!),
      selectedResources: Set<String>.unmodifiable(_selectedResources),
      resourcePermissions: Map<String, Set<ResourcePermission>>.unmodifiable({
        for (final entry in _resourcePermissions.entries)
          entry.key: Set<ResourcePermission>.unmodifiable(entry.value),
      }),
      selectedEngines: Set<String>.unmodifiable(_selectedEngines),
    );
    setState(() => _saving = true);
    PreparedProfileAvatar? preparedAvatar;
    String? mintedRecoveryCode;
    try {
      if (snapshot.pendingAvatarBytes != null) {
        preparedAvatar = await ProfileAvatarIngest.prepare(
          snapshot.pendingAvatarBytes!,
        );
      }
      final savedAvatarKey =
          preparedAvatar?.avatar.format() ?? snapshot.avatarKey;
      var operationActor = _authorization;
      await _validateManagingAdmin(operationActor);
      final policy = EditProfileScreen.policyFor(
        role: snapshot.role,
        selected: snapshot.features,
        existing: widget.profile?.policy,
        // A role change is authorship too: the Pages pane reseeded to the
        // new role's policy, and the save must write what it displayed.
        controlsShown:
            EditProfileScreen.showFeaturePolicyControls ||
            _policyTouched ||
            (widget.profile != null && widget.profile!.role != snapshot.role),
      );
      final existing = widget.profile;
      late final String savedProfileId;
      if (existing == null) {
        final creation = ProfileCreationService(widget.registry);
        final staged = await creation.createStaged(
          actor: operationActor,
          name: snapshot.name,
          role: snapshot.role,
          policy: policy,
          copyDefaultsFromActive: snapshot.copyDefaults,
          // A picked file is not authoritative until its bytes have been
          // durably staged below. Keep the pre-pick selection during staging.
          avatarKey: snapshot.avatarKey,
        );
        savedProfileId = staged.id;
        var stagedPublished = false;
        try {
          await ProfileAvatarMutation.runExclusive(staged.id, () async {
            await ProfileAvatarMutation.begin(staged.id, savedAvatarKey);
            if (preparedAvatar != null) {
              await ProfileAvatarIngest.writeCandidate(
                profileId: staged.id,
                prepared: preparedAvatar,
              );
            }
            if (snapshot.pin.isNotEmpty) {
              mintedRecoveryCode = await widget.pins.setPinAsAdmin(
                actor: operationActor,
                targetProfileId: staged.id,
                pin: snapshot.pin,
              );
            }
            await widget.registry.updateProfile(
              id: staged.id,
              avatarKey: savedAvatarKey,
              lockOnResume: snapshot.lockOnResume,
              inactivityTimeoutMinutes: snapshot.inactivityMinutes == 0
                  ? null
                  : snapshot.inactivityMinutes,
              clearInactivityTimeout: snapshot.inactivityMinutes == 0,
              actingProfileId: operationActor.profileId,
              actingAuthorizationRevision: operationActor.authorizationRevision,
              actingSessionEpoch: operationActor.sessionEpoch,
            );
            operationActor = await _refreshSameManagingAdmin(
              operationActor.profileId,
            );
            operationActor = await _applyResourceGrants(
              staged.id,
              snapshot,
              operationActor,
            );
            await _applyEngineAssignments(
              staged.id,
              snapshot.selectedEngines,
              operationActor,
            );
            // Visibility is the last registry step. Completion reconciles a
            // recovery-checkpoint exception against the committed row.
            await creation.completeStaged(
              profileId: staged.id,
              actor: operationActor,
            );
            stagedPublished = true;
            try {
              await ProfileAvatarIngest.commit(
                profileId: staged.id,
                avatarKey: savedAvatarKey,
              );
              await ProfileAvatarMutation.complete(staged.id);
            } catch (_) {
              // The profile is already visible and its selected file exists.
              // Keep the intent so bootstrap can finish cleanup idempotently.
            }
          });
        } catch (error, stackTrace) {
          final persisted = await widget.registry.getProfile(staged.id);
          if (!stagedPublished &&
              persisted?.lifecycle != UserProfileLifecycle.active) {
            await creation.rollbackStaged(staged.id);
            await ProfileAvatarMutation.complete(staged.id);
          }
          // An active projection whose recovery checkpoint still fails is not
          // safe to finalize: retain its avatar intent so bootstrap can either
          // roll forward the durable active row or remove the durable staging
          // row. `completeStaged` is the only path that may set published=true.
          Error.throwWithStackTrace(error, stackTrace);
        }
      } else {
        savedProfileId = existing.id;
        final expectedTimeout = snapshot.inactivityMinutes == 0
            ? null
            : snapshot.inactivityMinutes;
        await ProfileAvatarIngest.publish(
          registry: widget.registry,
          profileId: existing.id,
          avatarKey: savedAvatarKey,
          prepared: preparedAvatar,
          persist: () async {
            await widget.registry.updateProfile(
              id: existing.id,
              name: snapshot.name,
              avatarKey: savedAvatarKey,
              role: snapshot.role,
              policy: policy,
              lockOnResume: snapshot.lockOnResume,
              inactivityTimeoutMinutes: expectedTimeout,
              clearInactivityTimeout: expectedTimeout == null,
              actingProfileId: operationActor.profileId,
              actingAuthorizationRevision: operationActor.authorizationRevision,
              actingSessionEpoch: operationActor.sessionEpoch,
            );
          },
          wasPersisted: () async {
            final persisted = await widget.registry.getProfile(existing.id);
            return persisted?.name == snapshot.name.trim() &&
                persisted?.avatarKey == savedAvatarKey &&
                persisted?.role == snapshot.role &&
                persisted?.policy.encode() == policy.encode() &&
                persisted?.lockOnResume == snapshot.lockOnResume &&
                persisted?.inactivityTimeoutMinutes == expectedTimeout;
          },
        );
        operationActor = await _refreshSameManagingAdmin(
          operationActor.profileId,
        );
        if (snapshot.pin.isNotEmpty) {
          mintedRecoveryCode = await widget.pins.setPinAsAdmin(
            actor: operationActor,
            targetProfileId: existing.id,
            pin: snapshot.pin,
          );
          operationActor = await _refreshSameManagingAdmin(
            operationActor.profileId,
          );
        }
        operationActor = await _applyResourceGrants(
          savedProfileId,
          snapshot,
          operationActor,
        );
        await _applyEngineAssignments(
          savedProfileId,
          snapshot.selectedEngines,
          operationActor,
        );
      }
      _authorization = operationActor;
      if (!mounted) return;
      _avatarKey = savedAvatarKey;
      _features = Set<ProfileFeature>.from(policy.enabled);
      _seedDownloads = _features.contains(ProfileFeature.downloads);
      _seedRemote = _features.contains(ProfileFeature.remoteControl);
      _policyTouched = false;
      _pendingAvatarBytes = null;
      _pin.clear();
      // Saving the SIGNED-IN profile never crosses the gate, so the policy
      // mirrors (MainPage tab gating + ProfilePolicyGuard) must be told.
      if (ProfileRuntime.isProfileCommitted &&
          widget.profile?.id == ProfileRuntime.capture().profileId) {
        MainPageBridge.reloadProfilePolicy?.call();
      }
      final recoveryCode = mintedRecoveryCode;
      if (recoveryCode != null) {
        await _showRecoveryCode(snapshot.name, recoveryCode);
        if (!mounted) return;
      }
      await showWebDavSaveProgress(context, syncRevision);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ProfileAvatarRejected catch (rejected) {
      if (!mounted) return;
      setState(() => _saving = false);
      // The one failure with a user-actionable cause: name it instead of the
      // generic message.
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(rejected.message)));
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
    _ProfileEditSnapshot snapshot,
    ProfileAuthorizationContext operationActor,
  ) async {
    final resources = snapshot.resources;
    final service = ConnectionResourceService(
      registry: widget.registry,
      cipher: DeviceKeyProvider.cipher,
    );
    for (final resource in resources) {
      final existing = await widget.registry.getGrant(
        targetProfileId,
        resource.id,
      );
      final selected = snapshot.selectedResources.contains(resource.id);
      final desired =
          snapshot.resourcePermissions[resource.id] ??
          _defaultResourcePermissions(snapshot.role, snapshot.features);
      final desiredMask = desired.fold<int>(
        0,
        (mask, permission) => mask | permission.bit,
      );
      final bindingSlot = resource.type.singletonCredentialBindingSlot;
      final bindingMatches =
          bindingSlot == null ||
          await widget.registry.getBoundResourceId(
                targetProfileId,
                bindingSlot,
              ) ==
              resource.id;
      if (selected &&
          (existing == null ||
              existing.permissions != desiredMask ||
              !bindingMatches)) {
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

  Future<void> _applyEngineAssignments(
    String targetProfileId,
    Set<String> selectedEngineIds,
    ProfileAuthorizationContext operationActor,
  ) => ProfileEngineAssignmentService(widget.registry).apply(
    actor: operationActor,
    targetProfileId: targetProfileId,
    selectedEngineIds: selectedEngineIds,
  );

  Set<ResourcePermission> _defaultResourcePermissions(
    UserProfileRole role, [
    Set<ProfileFeature>? features,
  ]) => <ResourcePermission>{
    ResourcePermission.use,
    if ((features ?? _features).contains(ProfileFeature.downloads) ||
        (features ?? _features).contains(ProfileFeature.recordings))
      ResourcePermission.download,
    if (role != UserProfileRole.child &&
        (features ?? _features).contains(ProfileFeature.remoteTransfer))
      ResourcePermission.writeRemote,
  };

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

  /// The single toggle-on path for a connection row, shared by the row itself
  /// and the group's "All" action so the singleton-slot rule cannot diverge:
  /// selecting one credential of a singleton kind deselects its rivals.
  void _selectResource(ConnectionResource resource) {
    final singletonSlot = resource.type.singletonCredentialBindingSlot;
    if (singletonSlot != null) {
      for (final other in _resources!) {
        if (other.id != resource.id &&
            other.type.singletonCredentialBindingSlot == singletonSlot) {
          _selectedResources.remove(other.id);
          _resourcePermissions.remove(other.id);
        }
      }
    }
    _selectedResources.add(resource.id);
    _resourcePermissions.putIfAbsent(
      resource.id,
      () => _defaultResourcePermissions(_role),
    );
  }

  void _deselectResource(ConnectionResource resource) {
    _selectedResources.remove(resource.id);
  }

  /// Rows the target profile does not own — the only ones whose grant is
  /// editable here. Owned rows are always granted.
  Iterable<ConnectionResource> _editableIn(List<ConnectionResource> group) =>
      group.where((resource) => resource.ownerProfileId != widget.profile?.id);

  Future<void> _showDiagnostics() async {
    final report = await ProfileDiagnosticsService.collectJson(widget.registry);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profile diagnostics'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(report)),
        ),
        actions: <Widget>[
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
          _role == UserProfileRole.admin,
    );
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.profile == null ? 'Create profile' : 'Edit profile',
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
        body: Focus(
          descendantsAreFocusable: !_saving,
          descendantsAreTraversable: !_saving,
          child: AbsorbPointer(
            absorbing: _saving,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_saving) const LinearProgressIndicator(),
                _sectionLabel('Avatar'),
                _buildAvatarSection(),
                _sectionLabel('Identity'),
                TvTextField(
                  controller: _name,
                  autofocus: true,
                  inputFormatters: <TextInputFormatter>[
                    LengthLimitingTextInputFormatter(40),
                  ],
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                if (widget.profile == null)
                  SwitchListTile(
                    value: _copyDefaults,
                    title: const Text('Copy appearance and playback defaults'),
                    subtitle: const Text(
                      'Does not copy accounts, history, downloads, paths, or IDs.',
                    ),
                    onChanged: (value) => setState(() => _copyDefaults = value),
                  ),
                _sectionLabel('Role'),
                _buildRoleCards(),
                if (EditProfileScreen.showFeaturePolicyControls) ...[
                  const SizedBox(height: 12),
                  for (final feature in editableFeatures)
                    CheckboxListTile(
                      value:
                          _features.contains(feature) &&
                          ProfilePolicy(
                            enabled: _features,
                          ).allows(_role, feature),
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
                ],
                _sectionLabel('Lock'),
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
                      onPressed: _saving ? null : _removePinAsAdmin,
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
                  onChanged: (value) =>
                      setState(() => _inactivityMinutes = value ?? 0),
                ),
                _sectionLabel('Access'),
                if (_setupLoadError != null)
                  ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(_setupLoadError!),
                    trailing: TextButton(
                      onPressed: _loadSetupOptions,
                      child: const Text('Retry'),
                    ),
                  )
                else if (_engines == null)
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
                    onTap: _showDiagnostics,
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
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 64,
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
            descendantsAreFocusable: !_saving,
            descendantsAreTraversable: !_saving,
            child: AbsorbPointer(
              absorbing: _saving,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 32, 24),
                child: Column(
                  children: [
                    if (_saving) const LinearProgressIndicator(),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildTvSectionRail(colors),
                          const SizedBox(width: 18),
                          Expanded(
                            child: switch (_tvSection) {
                              _TvProfileSection.profile =>
                                _buildTvProfileSection(),
                              _TvProfileSection.pages => _buildTvPagesSection(),
                              _TvProfileSection.lock => _buildTvLockSection(),
                              _TvProfileSection.access =>
                                _buildTvAccessSection(),
                              _TvProfileSection.data => _buildTvDataSection(),
                            },
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
    const tabs = <(_TvProfileSection, IconData, String)>[
      (_TvProfileSection.profile, Icons.person_rounded, 'PROFILE'),
      (_TvProfileSection.pages, Icons.grid_view_rounded, 'PAGES'),
      (_TvProfileSection.access, Icons.group_rounded, 'ACCESS'),
      (_TvProfileSection.lock, Icons.lock_rounded, 'LOCK'),
      (_TvProfileSection.data, Icons.shield_rounded, 'DATA'),
    ];
    final saveIndex = tabs.length;
    Widget railItem({
      required int index,
      required Widget child,
      required VoidCallback? onPressed,
      Key? key,
      bool selected = false,
      ValueChanged<bool>? onFocusChange,
    }) => SizedBox(
      height: 56,
      child: _TvActionSurface(
        key: key,
        selected: selected,
        focusNode: _tvTabFocusNodes[index],
        onKeyEvent: (_, event) => _handleTvRailKey(index, event),
        onFocusChange: onFocusChange,
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
      child: Column(
        children: [
          for (var index = 0; index < tabs.length; index++) ...[
            railItem(
              index: index,
              key: ValueKey('tv-profile-tab-${tabs[index].$1.name}'),
              selected: _tvSection == tabs[index].$1,
              // Sections switch on focus so DPAD browsing previews each pane;
              // onPressed keeps touch/click working (and moves focus with the
              // tap, so section and focus can never diverge on hybrid
              // touch+DPAD devices).
              onFocusChange: (focused) =>
                  _onRailItemFocused(index, focused, tabs[index].$1),
              onPressed: () {
                setState(() => _tvSection = tabs[index].$1);
                _tvTabFocusNodes[index].requestFocus();
              },
              child: railLabel(tabs[index].$2, tabs[index].$3),
            ),
            const SizedBox(height: 8),
          ],
          const Spacer(),
          railItem(
            index: saveIndex,
            key: const ValueKey('tv-profile-save'),
            onFocusChange: (focused) =>
                _onRailItemFocused(saveIndex, focused, null),
            onPressed: _saving ? null : _save,
            child: railLabel(Icons.check_rounded, _saving ? 'SAVING…' : 'SAVE'),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleTvRailKey(int index, KeyEvent event) {
    // KeyRepeatEvent deliberately excluded: every rail hop rebuilds the
    // content pane, and a held DPAD sweeping five heavyweight panes at
    // auto-repeat rate is exactly the frame cost low-end TVs can't absorb.
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      // RIGHT falls through to directional traversal, which enters the
      // content pane; LEFT is swallowed so focus can't escape the screen.
      LogicalKeyboardKey.arrowLeft => 0,
      _ => null,
    };
    if (delta == null) return KeyEventResult.ignored;
    if (delta == 0) return KeyEventResult.handled;

    final target = (index + delta).clamp(0, _tvTabFocusNodes.length - 1);
    if (target == index) return KeyEventResult.handled;
    _railMoveInProgress = true;
    _tvTabFocusNodes[target].requestFocus();
    return KeyEventResult.handled;
  }

  /// Rail focus is only a section switch when it came from WITHIN the rail
  /// (UP/DOWN, or a tap that moved focus). Focus entering from the content
  /// pane is geometric — LEFT from deep in a scrolled list lands on
  /// whichever tab is vertically nearest — so it is redirected to the
  /// current section's tab instead of silently swapping the pane the user
  /// was editing.
  void _onRailItemFocused(int index, bool focused, _TvProfileSection? section) {
    if (!focused) return;
    final cameFromRail = _railMoveInProgress;
    _railMoveInProgress = false;
    if (section != null && _tvSection == section) return;
    if (cameFromRail) {
      if (section != null) setState(() => _tvSection = section);
      return;
    }
    final home = _TvProfileSection.values.indexOf(_tvSection);
    if (home == index) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tvTabFocusNodes[home].requestFocus();
    });
  }

  Widget _buildTvPagesSection() {
    bool on(ProfileFeature feature) =>
        ProfilePolicy(enabled: _features).allows(_role, feature);
    void toggle(ProfileFeature feature) {
      if (_saving) return;
      setState(() {
        _policyTouched = true;
        if (!_features.remove(feature)) _features.add(feature);
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
        child: _TvActionSurface(
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
                        _EnsureVisibleOnFocus(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _pickAvatarImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text(
                              'Choose image or GIF (this device only)',
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_pendingAvatarBytes != null &&
                      ProfileAvatarPolicy.userImagesSupported)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _pendingAvatarBytes = null),
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
                    controller: _name,
                    autofocus: true,
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
                    _EnsureVisibleOnFocus(
                      child: SwitchListTile(
                        value: _copyDefaults,
                        title: const Text(
                          'Copy appearance and playback defaults',
                        ),
                        onChanged: (value) =>
                            setState(() => _copyDefaults = value),
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
                  child: _pendingAvatarBytes != null
                      ? Image.memory(_pendingAvatarBytes!, fit: BoxFit.cover)
                      : ProfileAvatarView(
                          profileId: widget.profile?.id ?? 'staging-preview',
                          avatarKey: _avatarKey,
                          role: _role,
                          name: _name.text.isEmpty ? '?' : _name.text,
                          focused: true,
                        ),
                ),
              ),
              SizedBox(height: compact ? 12 : 24),
              Text(
                _name.text.trim().isEmpty ? 'New profile' : _name.text.trim(),
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
                    _role == UserProfileRole.child
                        ? 'Kid'
                        : _role.name[0].toUpperCase() + _role.name.substring(1),
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
    final selected = _pendingAvatarBytes == null && _avatarKey == keyName;
    return SizedBox(
      width: 78,
      height: 78,
      child: Tooltip(
        message: label,
        child: _TvActionSurface(
          selected: selected,
          onPressed: () => setState(() {
            _avatarKey = keyName;
            _pendingAvatarBytes = null;
          }),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ProfileAvatarView(
              profileId: widget.profile?.id ?? 'staging-preview',
              avatarKey: keyName,
              role: _role,
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
    Widget card(UserProfileRole role) => _TvActionSurface(
      selected: _role == role,
      onPressed: () => _setRole(role),
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
                    onPressed: _saving ? null : _removePinAsAdmin,
                    icon: const Icon(Icons.lock_open_rounded),
                    label: const Text('Admin reset: remove PIN'),
                  ),
                ),
              const SizedBox(height: 16),
              _EnsureVisibleOnFocus(
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  value: _lockOnResume,
                  title: const Text('Lock when the app resumes'),
                  subtitle: const Text('Require the PIN after leaving Debrify'),
                  onChanged: (value) => setState(() => _lockOnResume = value),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  tileColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 16),
              _TvAutoLockField(
                value: _inactivityMinutes,
                onChanged: (value) =>
                    setState(() => _inactivityMinutes = value),
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
              if (_setupLoadError != null)
                _EnsureVisibleOnFocus(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: Text(_setupLoadError!),
                    trailing: TextButton(
                      onPressed: _loadSetupOptions,
                      child: const Text('Retry'),
                    ),
                  ),
                )
              else if (_engines == null)
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
                  child: _TvActionSurface(
                    onPressed: _showDiagnostics,
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

  Future<void> _removePinAsAdmin() async {
    final revision = WebDavSyncSaveFeedback.instance.revision;
    await _removePinAsAdminLocally();
    if (mounted) await showWebDavSaveProgress(context, revision);
  }

  Future<void> _removePinAsAdminLocally() async {
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PIN protection removed')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN protection was not changed')),
      );
    }
  }

  Widget _buildAvatarSection() {
    final pending = _pendingAvatarBytes;
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
                        avatarKey: _avatarKey,
                        role: _role,
                        name: _name.text.isEmpty ? '?' : _name.text,
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
                      onPressed: _saving ? null : _pickAvatarImage,
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text(
                        'Choose image or GIF (this device only)',
                      ),
                    ),
                  if (pending != null)
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _pendingAvatarBytes = null),
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
                  role: _role,
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
                  role: _role,
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
    final selected = _pendingAvatarBytes == null && _avatarKey == key;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _saving
            ? null
            : () => setState(() {
                _avatarKey = key;
                _pendingAvatarBytes = null;
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
    final selected = _role == role;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        right: horizontal ? 8 : 0,
        bottom: horizontal ? 0 : 8,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _saving ? null : () => _setRole(role),
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
    final engines = _engines!;
    final ownEditor = widget.profile?.id == _authorization.profileId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _groupHeader(
          'Torrent engines',
          selected: _selectedEngines.length,
          total: engines.length,
          onAll: engines.isEmpty || ownEditor
              ? null
              : () => setState(
                  () => _selectedEngines.addAll(
                    engines.map((engine) => engine.id),
                  ),
                ),
          onNone: engines.isEmpty || ownEditor
              ? null
              : () => setState(_selectedEngines.clear),
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
              interactive: !ownEditor,
              child: CheckboxListTile(
                value: _selectedEngines.contains(engine.id),
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
                          _selectedEngines.add(engine.id);
                        } else {
                          _selectedEngines.remove(engine.id);
                        }
                      }),
              ),
            ),
      ],
    );
  }

  Widget _tvAccessFocusRow({required bool interactive, required Widget child}) {
    if (!PlatformUtil.isTelevision) return child;
    return interactive
        ? _EnsureVisibleOnFocus(child: child)
        : _TvReadOnlyScrollAnchor(child: child);
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
    final resources = _resources;
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
        .where((resource) => _selectedResources.contains(resource.id))
        .length;
    final editable = _editableIn(group).toList();
    return [
      _groupHeader(
        label,
        selected: selected,
        total: group.length,
        onAll: editable.isEmpty
            ? null
            : () => setState(() => editable.forEach(_selectResource)),
        onNone: editable.isEmpty
            ? null
            : () => setState(() => editable.forEach(_deselectResource)),
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
        interactive: interactive,
        child: CheckboxListTile(
          value: _selectedResources.contains(resource.id),
          title: Text(resource.label),
          subtitle: Text(
            resource.secretPending
                ? 'credentials pending owner sign-in'
                : resource.type.name,
          ),
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
          onChanged: interactive
              ? (selected) => setState(() {
                  if (selected == true) {
                    _selectResource(resource);
                  } else {
                    _deselectResource(resource);
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
