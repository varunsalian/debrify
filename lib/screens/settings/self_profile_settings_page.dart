import '../../services/webdav_sync/webdav_sync_save_feedback.dart';
import '../../widgets/webdav_sync/webdav_save_status.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/profiles/profile_avatar.dart';
import '../../models/profiles/user_profile.dart';
import '../../services/main_page_bridge.dart';
import '../../services/profiles/profile_authorization.dart';
import '../../services/profiles/profile_avatar_ingest.dart';
import '../../services/profiles/profile_avatar_policy.dart';
import '../../services/profiles/profile_lock_controller.dart';
import '../../services/profiles/profile_pin_service.dart';
import '../../services/profiles/profile_registry.dart';
import '../../widgets/profiles/profile_art.dart';
import '../../widgets/profiles/profile_avatar_view.dart';
import '../../widgets/tv_text_field.dart';
import 'widgets/settings_widgets.dart';

/// Self-service identity editor for the unlocked active profile.
///
/// It intentionally has no role, policy, connection, engine or household
/// controls. Those remain in the Admin editor and are also impossible to
/// change through the registry methods used here.
class SelfProfileSettingsPage extends StatefulWidget {
  const SelfProfileSettingsPage({
    super.key,
    required this.registry,
    required this.pins,
    required this.authorization,
    required this.profile,
  });

  final ProfileRegistry registry;
  final ProfilePinService pins;
  final ProfileAuthorizationContext authorization;
  final UserProfile profile;

  @override
  State<SelfProfileSettingsPage> createState() =>
      _SelfProfileSettingsPageState();
}

class _SelfProfileSettingsPageState extends State<SelfProfileSettingsPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.name,
  );
  final TextEditingController _currentPin = TextEditingController();
  final TextEditingController _newPin = TextEditingController();
  final TextEditingController _confirmPin = TextEditingController();

  late UserProfile _profile = widget.profile;
  late String? _avatarKey = widget.profile.avatarKey;
  Uint8List? _pendingAvatarBytes;
  bool _savingIdentity = false;
  bool _savingPin = false;
  String? _loadError;

  bool get _busy => _savingIdentity || _savingPin;

  @override
  void initState() {
    super.initState();
    _validateSession();
  }

  @override
  void dispose() {
    _name.dispose();
    _currentPin
      ..clear()
      ..dispose();
    _newPin
      ..clear()
      ..dispose();
    _confirmPin
      ..clear()
      ..dispose();
    super.dispose();
  }

  Future<void> _validateSession() async {
    try {
      final actor = await widget.authorization.validate(widget.registry);
      if (actor.id != widget.profile.id) {
        throw StateError('Only the active profile can edit itself');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'This profile session is no longer active');
      }
    }
  }

  Future<void> _pickAvatarImage() async {
    if (_busy) return;
    try {
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
      if (!mounted || _busy) return;
      setState(() => _pendingAvatarBytes = prepared.bytes);
    } on ProfileAvatarRejected catch (error) {
      _message(error.message);
    } on PlatformException {
      _message('The image picker is not available.');
    } catch (_) {
      _message('That image could not be opened.');
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

  Future<void> _saveIdentity() async {
    final revision = WebDavSyncSaveFeedback.instance.revision;
    await _saveIdentityLocally();
    if (mounted) await showWebDavSaveProgress(context, revision);
  }

  Future<void> _saveIdentityLocally() async {
    final name = _name.text.trim();
    if (_busy || name.isEmpty) {
      if (name.isEmpty) _message('Enter a profile name');
      return;
    }
    setState(() => _savingIdentity = true);
    try {
      final actor = await widget.authorization.validate(widget.registry);
      if (actor.id != _profile.id) {
        throw StateError('Active profile changed');
      }
      final prepared = _pendingAvatarBytes == null
          ? null
          : await ProfileAvatarIngest.prepare(_pendingAvatarBytes!);
      final savedAvatarKey = prepared?.avatar.format() ?? _avatarKey;
      await ProfileAvatarIngest.publish(
        registry: widget.registry,
        profileId: actor.id,
        avatarKey: savedAvatarKey,
        prepared: prepared,
        persist: () => widget.registry.updateActiveProfileIdentity(
          profileId: actor.id,
          name: name,
          avatarKey: savedAvatarKey,
          actingAuthorizationRevision:
              widget.authorization.authorizationRevision,
          actingSessionEpoch: widget.authorization.sessionEpoch,
        ),
        wasPersisted: () async {
          final persisted = await widget.registry.getProfile(actor.id);
          return persisted?.name == name &&
              persisted?.avatarKey == savedAvatarKey;
        },
      );
      final updated = await widget.registry.getProfile(actor.id);
      if (updated == null) throw StateError('Profile disappeared');
      final sessionCurrent = await _refreshCurrentSessionProfile(updated);
      if (!mounted) return;
      setState(() {
        if (sessionCurrent) {
          _profile = updated;
          _avatarKey = savedAvatarKey;
          _pendingAvatarBytes = null;
        }
        _savingIdentity = false;
      });
      if (sessionCurrent) _message('Profile updated');
    } on ProfileAvatarRejected catch (error) {
      if (mounted) setState(() => _savingIdentity = false);
      _message(error.message);
    } catch (_) {
      if (mounted) setState(() => _savingIdentity = false);
      _message('Profile could not be updated');
    }
  }

  Future<void> _changePin() async {
    final revision = WebDavSyncSaveFeedback.instance.revision;
    await _changePinLocally();
    if (mounted) await showWebDavSaveProgress(context, revision);
  }

  Future<void> _changePinLocally() async {
    final next = _newPin.text;
    if (_busy) return;
    if (!RegExp(r'^\d{4,8}$').hasMatch(next)) {
      _message('PIN must contain 4–8 digits');
      return;
    }
    if (next != _confirmPin.text) {
      _message('New PINs do not match');
      return;
    }
    if (_profile.hasPin && _currentPin.text.isEmpty) {
      _message('Enter your current PIN');
      return;
    }
    setState(() => _savingPin = true);
    try {
      final recovery = await widget.pins.setOwnPin(
        actor: widget.authorization,
        currentPin: _profile.hasPin ? _currentPin.text : null,
        newPin: next,
      );
      final sessionCurrent = await _refreshAfterPinChange();
      if (!mounted || !sessionCurrent) return;
      await _showRecoveryCode(recovery);
    } on ProfilePinDurabilityException catch (error) {
      final sessionCurrent = await _refreshAfterPinChange();
      if (!mounted || !sessionCurrent) return;
      final recovery = error.recoveryCode;
      if (recovery != null) {
        await _showRecoveryCode(recovery, durabilityWarning: true);
      } else {
        _message('PIN changed locally but could not be saved safely');
      }
    } on ProfileCurrentPinException catch (error) {
      if (mounted) setState(() => _savingPin = false);
      _message(_pinError(error.verification));
    } catch (_) {
      if (mounted) setState(() => _savingPin = false);
      _message('PIN could not be changed');
    }
  }

  Future<void> _removePin() async {
    final revision = WebDavSyncSaveFeedback.instance.revision;
    await _removePinLocally();
    if (mounted) await showWebDavSaveProgress(context, revision);
  }

  Future<void> _removePinLocally() async {
    if (_busy || !_profile.hasPin) return;
    if (_currentPin.text.isEmpty) {
      _message('Enter your current PIN');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove PIN protection?'),
        content: const Text(
          'Anyone using this device will be able to open this profile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove PIN'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingPin = true);
    try {
      await widget.pins.removeOwnPin(
        actor: widget.authorization,
        currentPin: _currentPin.text,
      );
      final sessionCurrent = await _refreshAfterPinChange();
      if (sessionCurrent) _message('PIN protection removed');
    } on ProfilePinDurabilityException {
      final sessionCurrent = await _refreshAfterPinChange();
      if (sessionCurrent) {
        _message('PIN removal could not be saved safely and may revert');
      }
    } on ProfileCurrentPinException catch (error) {
      if (mounted) setState(() => _savingPin = false);
      _message(_pinError(error.verification));
    } catch (_) {
      if (mounted) setState(() => _savingPin = false);
      _message('PIN protection was not changed');
    }
  }

  Future<bool> _refreshAfterPinChange() async {
    final updated = await widget.registry.getProfile(_profile.id);
    if (updated == null) throw StateError('Profile disappeared');
    final sessionCurrent = await _refreshCurrentSessionProfile(updated);
    if (!mounted) return false;
    setState(() {
      if (sessionCurrent) _profile = updated;
      _currentPin.clear();
      _newPin.clear();
      _confirmPin.clear();
      _savingPin = false;
    });
    return sessionCurrent;
  }

  Future<bool> _refreshCurrentSessionProfile(UserProfile updated) async {
    try {
      final actor = await widget.authorization.validate(widget.registry);
      if (actor.id != updated.id) return false;
    } catch (_) {
      return false;
    }
    final refreshed = ProfileLockController.instance.refreshProfileIfCurrent(
      updated,
    );
    if (!refreshed) return false;
    try {
      final actor = await widget.authorization.validate(widget.registry);
      if (actor.id != updated.id) return false;
    } catch (_) {
      return false;
    }
    if (!ProfileLockController.instance.isUnlocked) return false;
    MainPageBridge.reloadProfilePolicy?.call();
    return true;
  }

  String _pinError(ProfilePinVerification verification) =>
      switch (verification.result) {
        ProfilePinResult.locked => 'Profile is temporarily locked',
        ProfilePinResult.resetRequired => 'An Admin must reset this PIN',
        _ => 'Current PIN is incorrect',
      };

  Future<void> _showRecoveryCode(
    String code, {
    bool durabilityWarning = false,
  }) async {
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
              durabilityWarning
                  ? 'The PIN changed on this session, but the device could not '
                        'save it safely and it may revert after restart. Keep '
                        'this one-time recovery code and try again later.'
                  : 'This code can remove your PIN if you forget it. It is '
                        'shown only once—write it down or save it securely.',
            ),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('I saved it'),
          ),
        ],
      ),
    );
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: 'Edit your profile',
      body: _loadError != null
          ? Center(child: Text(_loadError!))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SettingsPageHeader(
                        icon: Icons.manage_accounts_rounded,
                        title: 'Your profile',
                        subtitle: 'Your name, picture and private PIN',
                      ),
                      const SizedBox(height: 24),
                      SettingsSection(
                        title: 'Identity',
                        children: [
                          _avatarEditor(),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: TvTextField(
                              key: const ValueKey('self-profile-name'),
                              controller: _name,
                              enabled: !_busy,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(40),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Name',
                              ),
                            ),
                          ),
                          SettingsTile(
                            key: const ValueKey('self-profile-save-identity'),
                            icon: Icons.save_rounded,
                            title: 'Save name and avatar',
                            subtitle: 'Only this profile is changed',
                            enabled: !_busy,
                            onTap: _saveIdentity,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      SettingsSection(
                        title: 'PIN protection',
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                if (_profile.hasPin) ...[
                                  _pinField(
                                    key: 'self-profile-current-pin',
                                    controller: _currentPin,
                                    label: 'Current PIN',
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                _pinField(
                                  key: 'self-profile-new-pin',
                                  controller: _newPin,
                                  label: _profile.hasPin
                                      ? 'New PIN'
                                      : 'Create PIN',
                                ),
                                const SizedBox(height: 12),
                                _pinField(
                                  key: 'self-profile-confirm-pin',
                                  controller: _confirmPin,
                                  label: 'Confirm new PIN',
                                ),
                              ],
                            ),
                          ),
                          SettingsTile(
                            key: const ValueKey('self-profile-change-pin'),
                            icon: Icons.lock_rounded,
                            title: _profile.hasPin ? 'Change PIN' : 'Set PIN',
                            subtitle: _profile.hasPin
                                ? 'Your current PIN is required'
                                : 'Protect this profile on shared devices',
                            enabled: !_busy,
                            onTap: _changePin,
                          ),
                          if (_profile.hasPin)
                            SettingsTile(
                              key: const ValueKey('self-profile-remove-pin'),
                              icon: Icons.lock_open_rounded,
                              title: 'Remove PIN',
                              subtitle: 'Current PIN required',
                              destructive: true,
                              enabled: !_busy,
                              onTap: _removePin,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _pinField({
    required String key,
    required TextEditingController controller,
    required String label,
  }) => TvTextField(
    key: ValueKey(key),
    controller: controller,
    enabled: !_busy,
    keyboardType: TextInputType.number,
    obscureText: true,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(8),
    ],
    decoration: InputDecoration(labelText: label),
  );

  Widget _avatarEditor() {
    final pending = _pendingAvatarBytes;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox.square(
                  dimension: 84,
                  child: pending != null
                      ? Image.memory(pending, fit: BoxFit.cover)
                      : ProfileAvatarView(
                          profileId: _profile.id,
                          avatarKey: _avatarKey,
                          role: _profile.role,
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
                    if (ProfileAvatarPolicy.userImagesSupported)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickAvatarImage,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: const Text(
                          'Choose image or GIF (this device only)',
                        ),
                      ),
                    if (pending != null)
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _pendingAvatarBytes = null),
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text('Discard image'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final art in ProfileArtRegistry.all)
                _avatarChoice(key: 'art:${art.id}', label: art.label),
              for (final icon in ProfileAvatar.legacyIconIds)
                _avatarChoice(key: icon, label: icon),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatarChoice({required String key, required String label}) {
    final selected = _pendingAvatarBytes == null && _avatarKey == key;
    return Tooltip(
      message: label,
      child: InkWell(
        key: ValueKey('self-avatar-$key'),
        borderRadius: BorderRadius.circular(12),
        onTap: _busy
            ? null
            : () => setState(() {
                _avatarKey = key;
                _pendingAvatarBytes = null;
              }),
        child: Container(
          width: 54,
          height: 54,
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
          child: ProfileAvatarView(
            profileId: _profile.id,
            avatarKey: key,
            role: _profile.role,
            name: label,
          ),
        ),
      ),
    );
  }
}
