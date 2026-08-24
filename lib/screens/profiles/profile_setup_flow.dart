import 'package:flutter/material.dart';

import '../../models/profiles/profile_policy.dart';
import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_bootstrap.dart';
import '../../services/profiles/profile_creation_service.dart';
import '../../services/profiles/profile_engine_assignment_service.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_registry.dart';
import '../../services/profiles/profile_runtime.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/platform_util.dart';
import '../../widgets/onboarding/onboarding_theme.dart';
import '../../widgets/onboarding/onboarding_focus.dart';
import '../../widgets/profiles/profile_art.dart';
import '../../widgets/tv_text_field.dart';
import 'edit_profile_screen.dart';

/// The profile questionnaire — the policy author now that the raw feature
/// matrix is hidden (dev/design/mockups/profile_features_mockup, mock v6).
///
/// Five steps: identity → role (the PRESET — picking one pre-answers every
/// later step) → search power → source pages → abilities, then a Review that
/// speaks Can/Can't. Presets prefill, they never lock: any answer diverges
/// without ceremony. EDIT mode seeds every answer from the profile's CURRENT
/// policy and lands on Review — presets only seed CREATE.
///
/// Deliberately thin where EditProfileScreen is deep: PIN, uploaded/GIF
/// avatars, lock-on-resume and the rest of identity's long tail stay in the
/// full editor, reachable from Review ("Full editor"). The flow writes
/// exactly (name, role, art avatar, policy).
///
/// Wrapped in [OnboardingTheme.scope] like the wall and onboarding — gate
/// surfaces keep the fixed Spotlight look under any app theme. One question
/// per screen on every tier, which is what makes it DPAD-friendly by
/// construction; [OnboardFocusable] supplies the TV focus grid.
class ProfileSetupFlow extends StatefulWidget {
  const ProfileSetupFlow({
    super.key,
    required this.registry,
    required this.authorization,
    this.profile,
  });

  final ProfileRegistry registry;
  final ProfileAuthorizationContext authorization;

  /// Null = create. Present = edit: answers seed from its policy and the
  /// flow opens on Review.
  final UserProfile? profile;

  /// Push the flow full-screen on the root navigator under the fixed
  /// Spotlight look (the InitialSetupFlow.show pattern). Returns true when a
  /// profile was created or changed.
  static Future<bool> show(BuildContext context, {UserProfile? profile}) async {
    final registry = ProfileBootstrap.registry;
    final authorization = await ProfileAuthorizationContext.capture(registry);
    if (!context.mounted) return false;
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OnboardingTheme.scope(
          ProfileSetupFlow(
            registry: registry,
            authorization: authorization,
            profile: profile,
          ),
        ),
      ),
    );
    return result ?? false;
  }

  @override
  State<ProfileSetupFlow> createState() => _ProfileSetupFlowState();
}

enum _QStep { identity, role, search, sources, abilities, review }

class _ProfileSetupFlowState extends State<ProfileSetupFlow> {
  final OnboardFocusController _focus = OnboardFocusController();
  final TextEditingController _name = TextEditingController();
  final FocusNode _nameNode = FocusNode(debugLabel: 'profile-name-field');

  late _QStep _step;
  String? _artId;
  UserProfileRole _role = UserProfileRole.member;

  // The questionnaire's answers. Role selection re-seeds these from the
  // preset in CREATE mode; edit mode seeds them once from the profile.
  bool _keywordSearch = true;
  bool _debrifyTv = true;
  bool _stremioTv = true;
  bool _iptv = true;
  bool _youtube = true;
  bool _downloads = true;
  bool _remote = true;
  bool _manageOwnSources = true;
  bool _cloudFiles = true;

  // Where the coupled pairs (downloads/recordings, remote/remoteTransfer)
  // started, so an untouched edit-save never re-couples a policy that the
  // old feature matrix split.
  bool _seedDownloads = true;
  bool _seedRemote = true;

  // Create-only: copy the creator's appearance & player defaults onto the
  // new profile (ProfileCreationService's reviewed allowlist). Unticked by
  // default — a fresh profile starting from stock is the less surprising
  // outcome; inheriting the admin's tuned setup is the opt-in.
  bool _copyDefaults = false;

  bool _saving = false;
  // Changes made through the embedded full editor must survive a BACK out
  // of Review — show() reports "changed" for them too.
  bool _changedElsewhere = false;
  String? _error;

  bool get _isEdit => widget.profile != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.profile;
    if (existing == null) {
      _step = _QStep.identity;
      _seedFromRole(UserProfileRole.member);
    } else {
      _step = _QStep.review;
      _name.text = existing.name;
      _role = existing.role;
      final avatar = ProfileAvatar.tryParse(existing.avatarKey);
      if (avatar?.kind == ProfileAvatarKind.art) _artId = avatar!.id;
      _seedFromPolicy(existing.policy, existing.role);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _name.dispose();
    _nameNode.dispose();
    super.dispose();
  }

  void _seedFromRole(UserProfileRole role) {
    _seedFromPolicy(ProfilePolicy.defaultsFor(role), role);
  }

  void _seedFromPolicy(ProfilePolicy policy, UserProfileRole role) {
    bool on(ProfileFeature f) => policy.allows(role, f);
    _keywordSearch = on(ProfileFeature.keywordSearch);
    _debrifyTv = on(ProfileFeature.debrifyTv);
    _stremioTv = on(ProfileFeature.stremioTv);
    _iptv = on(ProfileFeature.iptv);
    _youtube = on(ProfileFeature.youtube);
    _downloads = on(ProfileFeature.downloads);
    _remote = on(ProfileFeature.remoteControl);
    _manageOwnSources = on(ProfileFeature.addonsAndEngines);
    _cloudFiles = on(ProfileFeature.cloudFiles);
    _seedDownloads = _downloads;
    _seedRemote = _remote;
  }

  /// The policy the answers describe: a BASE with the questionnaire's
  /// tunables applied on top. The base is the profile's CURRENT policy for
  /// an edit with an unchanged role — an untouched save must be an identity
  /// operation, so v1-era customization of unasked features (adult content,
  /// trackers, operations) survives a Review round-trip. Create, or an edit
  /// that CHANGES the role, starts from the new role's defaults instead: a
  /// role change is a re-preset by design. The role ceiling clamps at
  /// evaluation regardless.
  ProfilePolicy _buildPolicy() {
    final existing = widget.profile;
    final rolePreset = existing == null || existing.role != _role;
    final enabled = Set<ProfileFeature>.from(
      rolePreset
          ? ProfilePolicy.defaultsFor(_role).enabled
          : existing.policy.enabled,
    );
    void put(ProfileFeature feature, bool on) {
      if (on) {
        enabled.add(feature);
      } else {
        enabled.remove(feature);
      }
    }

    put(ProfileFeature.keywordSearch, _keywordSearch);
    put(ProfileFeature.debrifyTv, _debrifyTv);
    put(ProfileFeature.stremioTv, _stremioTv);
    put(ProfileFeature.iptv, _iptv);
    put(ProfileFeature.youtube, _youtube);
    put(ProfileFeature.downloads, _downloads);
    put(ProfileFeature.remoteControl, _remote);
    put(ProfileFeature.addonsAndEngines, _manageOwnSources);
    put(ProfileFeature.cloudFiles, _cloudFiles);
    // The paired features follow their toggle only when the answer actually
    // moved — an untouched edit-save must not re-couple a policy where
    // downloads/recordings (or remote/remoteTransfer) were split by the old
    // feature matrix.
    if (rolePreset || _downloads != _seedDownloads) {
      put(ProfileFeature.recordings, _downloads);
    }
    if (rolePreset || _remote != _seedRemote) {
      put(ProfileFeature.remoteTransfer, _remote);
    }
    return ProfilePolicy(enabled: enabled);
  }

  void _go(_QStep step) {
    _focus.clearStep();
    setState(() {
      _step = step;
      _error = null;
    });
  }

  void _next() {
    switch (_step) {
      case _QStep.identity:
        if (_name.text.trim().isEmpty) {
          setState(() => _error = 'Give this profile a name first.');
          return;
        }
        _go(_QStep.role);
      case _QStep.role:
        _go(_QStep.search);
      case _QStep.search:
        _go(_QStep.sources);
      case _QStep.sources:
        _go(_QStep.abilities);
      case _QStep.abilities:
        _go(_QStep.review);
      case _QStep.review:
        break;
    }
  }

  void _back() {
    switch (_step) {
      case _QStep.identity:
        Navigator.of(context).pop(false);
      case _QStep.role:
        _go(_QStep.identity);
      case _QStep.search:
        _go(_QStep.role);
      case _QStep.sources:
        _go(_QStep.search);
      case _QStep.abilities:
        _go(_QStep.sources);
      case _QStep.review:
        if (_isEdit) {
          Navigator.of(context).pop(_changedElsewhere);
        } else {
          _go(_QStep.abilities);
        }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final actor = widget.authorization;
      final policy = _buildPolicy();
      final artKey = _artId == null ? null : 'art:$_artId';
      final existing = widget.profile;
      if (existing == null) {
        // The editor's create path: STAGED first, published only when every
        // step lands, rolled back (row + private bytes) on failure — a
        // half-created profile must never survive. createStaged also owns
        // the optional defaults copy (reviewed allowlist).
        final creation = ProfileCreationService(widget.registry);
        final staged = await creation.createStaged(
          actor: actor,
          name: _name.text.trim(),
          role: _role,
          policy: policy,
          copyDefaultsFromActive: _copyDefaults,
          avatarKey: artKey,
        );
        try {
          // Torrent engines are per-profile file copies, NOT connection
          // resources — the registry's default-grant seeding cannot cover
          // them. Match the full editor's create default: a new profile
          // starts with every engine its creator has; trimming engines is
          // an edit-time decision (full editor → Access). Non-fatal by
          // design: the profile must survive an engine-copy failure, and
          // the full editor can repair the assignment.
          try {
            // createStaged moves authorization revisions; a stale actor
            // would be rejected by the engine service's admin revalidation.
            final freshActor = await ProfileAuthorizationContext.capture(
              widget.registry,
            );
            final engines = ProfileEngineAssignmentService(widget.registry);
            final available = await engines.listForTarget(
              actor: freshActor,
              targetProfileId: staged.id,
            );
            final fromManager = available
                .where((engine) => engine.availableFromManager)
                .map((engine) => engine.id)
                .toSet();
            if (fromManager.isNotEmpty) {
              await engines.apply(
                actor: freshActor,
                targetProfileId: staged.id,
                selectedEngineIds: fromManager,
              );
            }
          } catch (error) {
            debugPrint(
              'ProfileSetupFlow engine seeding failed (${error.runtimeType})',
            );
          }
          await creation.completeStaged(
            profileId: staged.id,
            actor: await ProfileAuthorizationContext.capture(widget.registry),
          );
        } catch (error, stackTrace) {
          // completeStaged can throw AFTER the row durably committed (a
          // recovery-checkpoint retry failing) — the editor's guard: never
          // roll back a row that made it to active, or a real profile and
          // all its data would be deleted over a checkpoint hiccup.
          final persisted = await widget.registry.getProfile(staged.id);
          if (persisted?.lifecycle != UserProfileLifecycle.active) {
            await creation.rollbackStaged(staged.id);
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      } else {
        await widget.registry.updateProfile(
          id: existing.id,
          name: _name.text.trim(),
          role: _role,
          policy: policy,
          // Only write the avatar when the flow actually picked art —
          // never clobber an uploaded/GIF avatar with null.
          avatarKey: artKey ?? existing.avatarKey,
          actingProfileId: actor.profileId,
          actingAuthorizationRevision: actor.authorizationRevision,
          actingSessionEpoch: actor.sessionEpoch,
        );
      }
      // Saving the SIGNED-IN profile never crosses the gate, so the policy
      // mirrors (MainPage tab gating + ProfilePolicyGuard) must be told.
      if (existing != null &&
          ProfileRuntime.isProfileCommitted &&
          existing.id == ProfileRuntime.capture().profileId) {
        MainPageBridge.reloadProfilePolicy?.call();
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('ProfileSetupFlow save failed (${error.runtimeType})');
      if (!mounted) return;
      setState(() {
        _saving = false;
        // The registry's admin invariant is the one failure retrying can't
        // fix — name it instead of the generic line.
        _error = error is StateError
            ? 'Debrify needs at least one Admin who can manage profiles — '
                  'this change would remove the last one.'
            : 'Could not save this profile. Try again.';
      });
    }
  }

  Future<void> _openFullEditor() async {
    final existing = widget.profile;
    if (existing == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(
          registry: widget.registry,
          pins: ProfilePinService(registry: widget.registry),
          authorization: widget.authorization,
          profile: existing,
        ),
      ),
    );
    if (changed == true && mounted) {
      _changedElsewhere = true;
      final refreshed = await widget.registry.getProfile(existing.id);
      if (refreshed != null && mounted) {
        setState(() {
          _name.text = refreshed.name;
          _role = refreshed.role;
          _seedFromPolicy(refreshed.policy, refreshed.role);
        });
      }
    }
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final app = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                const Color(0xFF0D1420),
                Color.lerp(
                  const Color(0xFF0D1420),
                  const Color(0xFF151D2A),
                  0.34,
                )!,
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 600;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 22 : 32,
                        vertical: 18,
                      ),
                      child: _buildStep(context, app, compact),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context, ThemeData app, bool compact) {
    final (eyebrow, title, subtitle) = switch (_step) {
      _QStep.identity => (
        _isEdit ? '${_name.text} · identity' : 'New profile · step 1 of 5',
        'Name them.',
        'A name and a look — a PIN and photo avatars live in the full '
            'editor, any time.',
      ),
      _QStep.role => (
        _stepEyebrow(2),
        'Who is this for?',
        'This picks a starting point — every next step arrives already '
            'answered and can be changed.',
      ),
      _QStep.search => (
        _stepEyebrow(3),
        'How can ${_displayName()} search?',
        'Finding by title always works — their catalogs answer with '
            'posters. This is only about raw keyword search.',
      ),
      _QStep.sources => (
        _stepEyebrow(4),
        'Which pages can ${_displayName()} open?',
        "Pages that are off simply don't exist for this profile — no tab, "
            'no rows, no search results.',
      ),
      _QStep.abilities => (
        _stepEyebrow(5),
        'Beyond watching?',
        'What this profile may do with your accounts and devices.',
      ),
      _QStep.review => (
        _isEdit ? '${_displayName()} · review' : 'New profile · review',
        "${_displayName()}'s corner of Debrify",
        'Presets prefill, they never lock — re-run any step, or open the '
            'full editor for PIN, photo avatars and the rest.',
      ),
    };

    final content = switch (_step) {
      _QStep.identity => _identityStep(),
      _QStep.role => _roleStep(),
      _QStep.search => _searchStep(),
      _QStep.sources => _sourcesStep(),
      _QStep.abilities => _abilitiesStep(),
      _QStep.review => _reviewStep(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          eyebrow.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 2.2,
            color: Color(0x6BFFFFFF),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 27,
            height: 1.06,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.46,
              color: Color(0x99FFFFFF),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(child: SingleChildScrollView(child: content)),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFF87171), fontSize: 12),
          ),
        ],
        const SizedBox(height: 12),
        // The DPAD grid has no gap-bridging: the footer must sit on the row
        // right after each step's last focusable row or a remote can never
        // reach it.
        _footer(switch (_step) {
          // Create shows the copy-defaults card at row 2; edit doesn't.
          _QStep.identity => _isEdit ? 2 : 3,
          _QStep.role => 3,
          _QStep.search => 2,
          _QStep.sources => 4,
          _QStep.abilities => 4,
          _QStep.review => _isEdit ? 2 : 1,
        }),
        const SizedBox(height: 6),
        _dots(),
      ],
    );
  }

  String _displayName() {
    final name = _name.text.trim();
    return name.isEmpty ? 'this profile' : name;
  }

  String _stepEyebrow(int n) {
    final who = _name.text.trim();
    final role = switch (_role) {
      UserProfileRole.admin => 'Admin',
      UserProfileRole.member => 'Member',
      UserProfileRole.child => 'Kid',
    };
    final prefix = who.isEmpty ? 'New profile' : '$who · $role';
    return '$prefix · step $n of 5';
  }

  Widget _dots() {
    if (_step == _QStep.review) return const SizedBox(height: 4);
    final active = _QStep.values.indexOf(_step);
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2.5),
              width: i == active ? 14 : 5,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i == active
                    ? const Color(0xFFE23D4C)
                    : const Color(0x40FFFFFF),
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(int row) {
    final label = switch (_step) {
      _QStep.abilities => 'Review',
      _QStep.review => _saving
          ? 'Saving…'
          : _isEdit
          ? 'Save changes'
          : 'Create ${_displayName()}',
      _ => 'Next',
    };
    return OnboardFocusable(
      controller: _focus,
      cell: OnboardCell(row, 0),
      autofocus: PlatformUtil.isTelevision && _step == _QStep.review,
      enabled: !_saving,
      onActivate: _step == _QStep.review ? _save : _next,
      builder: (context, focused) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: focused ? Colors.white : const Color(0xF2FFFFFF),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF0B0E14),
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ),
      ),
    );
  }

  // ── steps ────────────────────────────────────────────────────────────────

  Widget _identityStep() {
    // The name field joins the DPAD grid the key_step way: its focus node is
    // registered at row 0 so UP/DOWN reach it like any card. Registration is
    // an idempotent map put, safe on every rebuild of this step.
    _focus.register(const OnboardCell(0, 0), _nameNode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TvTextField(
          controller: _name,
          focusNode: _nameNode,
          autofocus: PlatformUtil.isTelevision,
          labelText: 'Name',
          hintText: 'Who watches here?',
        ),
        const SizedBox(height: 16),
        Text(
          'LOOK',
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < ProfileArtRegistry.all.length; i++)
              _artTile(ProfileArtRegistry.all[i], i),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'GIFs and photos live in the full editor — living art animates on '
          'the profile screen.',
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
        if (!_isEdit) ...[
          const SizedBox(height: 14),
          _optionCard(
            row: 2,
            selected: _copyDefaults,
            check: true,
            onActivate: () => setState(() => _copyDefaults = !_copyDefaults),
            title: 'Start from my settings',
            description:
                'Copy appearance and player defaults — theme, TV scale, '
                'subtitle language — from your profile. Off = stock '
                'defaults.',
          ),
        ],
      ],
    );
  }

  Widget _artTile(ProfileArt art, int index) {
    final selected = _artId == art.id;
    return OnboardFocusable(
      controller: _focus,
      cell: OnboardCell(1, index),
      onActivate: () =>
          setState(() => _artId = selected ? null : art.id),
      semanticLabel: art.label,
      builder: (context, focused) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: art.color.withValues(alpha: selected ? 0.85 : 0.35),
          border: Border.all(
            color: selected || focused
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.10),
            width: 1.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  Widget _roleStep() {
    Widget card(
      UserProfileRole role,
      int row,
      String name,
      String tag,
      String desc,
    ) {
      final selected = _role == role;
      return _optionCard(
        row: row,
        selected: selected,
        onActivate: () => setState(() {
          _role = role;
          if (!_isEdit) _seedFromRole(role);
        }),
        title: name,
        trailing: tag,
        description: desc,
      );
    }

    return Column(
      children: [
        card(
          UserProfileRole.admin,
          0,
          'Admin',
          'RUNS THE DEVICE',
          'Everything, including managing services and other profiles.',
        ),
        card(
          UserProfileRole.member,
          1,
          'Member',
          'WATCHES FREELY',
          'Watches and downloads everything, changes nothing. No cloud '
              'file browsing.',
        ),
        card(
          UserProfileRole.child,
          2,
          'Kid',
          'CURATED CORNER',
          'Only shelves and channels you curate. No keyword search, no '
              'live TV, no downloads — NSFW filtering is always on.',
        ),
      ],
    );
  }

  Widget _searchStep() {
    return Column(
      children: [
        _optionCard(
          row: 0,
          selected: !_keywordSearch,
          onActivate: () => setState(() => _keywordSearch = false),
          title: 'By title, in their catalogs',
          description:
              'Type a name, get the poster — from the sources this profile '
              'has. No release lists.',
          footnote: 'KEYWORD SEARCH OFF',
        ),
        _optionCard(
          row: 1,
          selected: _keywordSearch,
          onActivate: () => setState(() => _keywordSearch = true),
          title: 'Plus keyword search',
          description:
              'Raw release search across the profile\'s torrent engines, '
              'ugly names and all.',
          footnote: 'KEYWORD SEARCH ON',
        ),
        if (!_isEdit) _presetNote(),
      ],
    );
  }

  Widget _sourcesStep() {
    Widget tile(
      int index,
      String name,
      String sub,
      bool value,
      ValueChanged<bool> set,
    ) {
      return _optionCard(
        row: index,
        selected: value,
        check: true,
        onActivate: () => setState(() => set(!value)),
        title: name,
        description: sub,
      );
    }

    return Column(
      children: [
        tile(
          0,
          'Debrify TV',
          'Channels curated on this device',
          _debrifyTv,
          (v) => _debrifyTv = v,
        ),
        tile(
          1,
          'Stremio TV',
          'Addon live channels',
          _stremioTv,
          (v) => _stremioTv = v,
        ),
        tile(
          2,
          'Live TV',
          'IPTV playlists & guide',
          _iptv,
          (v) => _iptv = v,
        ),
        tile(
          3,
          'YouTube',
          'The YouTube tab',
          _youtube,
          (v) => _youtube = v,
        ),
        if (!_isEdit) _presetNote(),
      ],
    );
  }

  Widget _abilitiesStep() {
    Widget tile(
      int index,
      String name,
      String sub,
      bool value,
      ValueChanged<bool> set,
    ) {
      return _optionCard(
        row: index,
        selected: value,
        check: true,
        onActivate: () => setState(() => set(!value)),
        title: name,
        description: sub,
      );
    }

    return Column(
      children: [
        tile(
          0,
          'Download & record',
          "Save things offline and use the DVR. Uses this device's storage "
              "and your accounts' quotas.",
          _downloads,
          (v) => _downloads = v,
        ),
        tile(
          1,
          'Remote',
          'Control other Debrify devices and send this setup to them.',
          _remote,
          (v) => _remote = v,
        ),
        tile(
          2,
          'Manage own sources',
          'Install or remove their own addons and torrent engines.',
          _manageOwnSources,
          (v) => _manageOwnSources = v,
        ),
        tile(
          3,
          'Cloud files',
          'Browse the raw file lists on connected accounts — including '
              'yours, if shared.',
          _cloudFiles,
          (v) => _cloudFiles = v,
        ),
        if (!_isEdit) _presetNote(),
      ],
    );
  }

  Widget _presetNote() {
    final label = switch (_role) {
      UserProfileRole.admin => 'Admin',
      UserProfileRole.member => 'Member',
      UserProfileRole.child => 'Kid',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        'Pre-filled by the $label preset — tap a card to change it.',
        style: const TextStyle(fontSize: 11, color: Color(0xFFFF7A85)),
      ),
    );
  }

  Widget _reviewStep() {
    final policy = _buildPolicy();
    bool can(ProfileFeature f) => policy.allows(_role, f);
    final canChips = <String>[
      'Home shelves',
      'Search by title',
      if (can(ProfileFeature.keywordSearch)) 'Keyword search',
      if (can(ProfileFeature.debrifyTv)) 'Debrify TV',
      if (can(ProfileFeature.stremioTv)) 'Stremio TV',
      if (can(ProfileFeature.iptv)) 'Live TV',
      if (can(ProfileFeature.youtube)) 'YouTube',
      if (can(ProfileFeature.downloads)) 'Downloads & recording',
      if (can(ProfileFeature.remoteControl)) 'Remote',
      if (can(ProfileFeature.addonsAndEngines)) 'Manage own sources',
      if (can(ProfileFeature.cloudFiles)) 'Cloud files',
    ];
    final cantChips = <String>[
      if (!can(ProfileFeature.keywordSearch)) 'Keyword search',
      if (!can(ProfileFeature.debrifyTv)) 'Debrify TV',
      if (!can(ProfileFeature.stremioTv)) 'Stremio TV',
      if (!can(ProfileFeature.iptv)) 'Live TV',
      if (!can(ProfileFeature.youtube)) 'YouTube',
      if (!can(ProfileFeature.downloads)) 'Downloads & recording',
      if (!can(ProfileFeature.remoteControl)) 'Remote',
      if (!can(ProfileFeature.addonsAndEngines)) 'Manage own sources',
      if (!can(ProfileFeature.cloudFiles)) 'Cloud files',
    ];

    Widget chips(List<String> labels, {required bool on}) => Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final label in labels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: on
                ? BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(99),
                  )
                : BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    borderRadius: BorderRadius.circular(99),
                  ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: on
                    ? Colors.white.withValues(alpha: 0.92)
                    : Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
      ],
    );

    Widget header(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 10,
          letterSpacing: 2,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.42),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header('CAN'),
        chips(canChips, on: true),
        if (cantChips.isNotEmpty) ...[
          header("CAN'T"),
          chips(cantChips, on: false),
        ],
        if (_isEdit && widget.profile!.role != _role) ...[
          const SizedBox(height: 12),
          const Text(
            "Role changed — abilities the questions don't cover reset to "
            "the new role's defaults.",
            style: TextStyle(fontSize: 11, color: Color(0xFFFF7A85)),
          ),
        ],
        const SizedBox(height: 18),
        _reviewAction(
          row: 0,
          icon: Icons.tune_rounded,
          title: 'Re-run the questions',
          subtitle: 'Walk the five steps again with the current answers',
          onActivate: () => _go(_QStep.identity),
        ),
        if (_isEdit)
          _reviewAction(
            row: 1,
            icon: Icons.manage_accounts_rounded,
            title: 'Full editor',
            subtitle: 'PIN, avatars, shared sources & torrent engines',
            onActivate: _openFullEditor,
          ),
      ],
    );
  }

  Widget _reviewAction({
    required int row,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onActivate,
  }) {
    return OnboardFocusable(
      controller: _focus,
      cell: OnboardCell(row, 0),
      onActivate: onActivate,
      builder: (context, focused) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: focused ? 0.15 : 0.055),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: Colors.white.withValues(alpha: focused ? 0.72 : 0.07),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionCard({
    required int row,
    required bool selected,
    required VoidCallback onActivate,
    required String title,
    required String description,
    String? trailing,
    String? footnote,
    bool check = false,
  }) {
    return OnboardFocusable(
      controller: _focus,
      cell: OnboardCell(row, 0),
      autofocus: PlatformUtil.isTelevision && row == 0,
      onActivate: onActivate,
      semanticLabel: title,
      builder: (context, focused) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(
            alpha: selected ? 0.15 : 0.055,
          ),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            width: 1.5,
            color: Colors.white.withValues(
              alpha: focused
                  ? 0.85
                  : selected
                  ? 0.72
                  : 0.07,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (trailing != null)
                  Text(
                    trailing,
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                if (check)
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: selected ? const Color(0xFFE23D4C) : null,
                      border: selected
                          ? null
                          : Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: Colors.white,
                          )
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            if (footnote != null) ...[
              const SizedBox(height: 9),
              Text(
                footnote,
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.38),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
