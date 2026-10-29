import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/tv_text_field.dart';
import '../application/smb_contracts.dart';
import '../application/smb_upload_providers.dart';
import '../application/smb_upload_status_notifier.dart';
import '../application/smb_uploader.dart';
import '../models/smb_target.dart';
import '../models/smb_upload_models.dart';

/// The SMB half of the recording settings page.
///
/// Owns the share form: it loads the stored [SmbTarget] and password from the
/// settings store, lets the user edit them, and hands a saved target back to
/// the coordinator so it reruns its upload pass. The status line is pushed by
/// the coordinator, so nothing here polls or owns a timer.
///
/// Every control is a normal focus-traversal stop (no hover-only action) and
/// nothing here autofocuses, so a remote can reach and operate the whole form.
class SmbUploadSection extends ConsumerStatefulWidget {
  const SmbUploadSection({super.key});

  @override
  ConsumerState<SmbUploadSection> createState() => _SmbUploadSectionState();
}

class _SmbUploadSectionState extends ConsumerState<SmbUploadSection> {
  static const _badAddress = r'Enter an address like \\nas\share';

  final _address = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _domain = TextEditingController();

  /// Null until the stored target and password have been read.
  SmbTarget? _target;
  bool _deleteLocal = false;
  bool _busy = false;

  /// Result of the last "Test connection", or [_badAddress] after a save was
  /// rejected. Cleared whenever the user edits or tries again.
  String? _notice;

  /// True while the address field holds text that will not parse; drives the
  /// field's error text and its opacity.
  bool _addressRejected = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _address.dispose();
    _user.dispose();
    _password.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = ref.read(smbSettingsStoreProvider);
    SmbTarget target;
    String? password;
    try {
      target = await store.readTarget();
      password = await store.readPassword();
    } catch (_) {
      // An unreadable store still leaves a usable form: it starts empty and
      // the user's next save writes over whatever could not be read.
      target = const SmbTarget();
    }
    if (!mounted) return;
    setState(() {
      _target = target;
      _deleteLocal = target.deleteLocalAfterUpload;
      _address.text = target.displayAddress;
      _user.text = target.user;
      _domain.text = target.domain;
      _password.text = password ?? '';
    });
  }

  /// The form's values as a target. [enabled] comes from the switch; the
  /// address the user just typed is authoritative for everything else.
  SmbTarget _draft({required bool enabled}) {
    final parsed = SmbTarget.parseAddress(_address.text);
    final base = parsed ?? const SmbTarget();
    return base.copyWith(
      enabled: enabled,
      user: _user.text.trim(),
      domain: _domain.text.trim(),
      deleteLocalAfterUpload: _deleteLocal,
    );
  }

  /// Save from the button. An address that does not parse is a draft error:
  /// it shows on the field and nothing is written.
  void _saveFromForm() {
    if (_busy) return;
    if (SmbTarget.parseAddress(_address.text) == null) {
      setState(() => _addressRejected = true);
      return;
    }
    unawaited(_save(_draft(enabled: true)));
  }

  Future<void> _save(SmbTarget target) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
      _addressRejected = false;
    });
    final store = ref.read(smbSettingsStoreProvider);
    // The password a save writes: what the user just typed, else the secret
    // that is already stored. Switching the share off happens from the
    // subtitle row, where the form (and its controller) is not on screen, so
    // there is no field to read and the secret is dropped instead.
    final typed = _password.text;
    final secret = target.enabled
        ? (typed.isNotEmpty ? typed : await _readPassword(store))
        : null;
    try {
      await store.writeTarget(target);
      await store.writePassword(secret);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _notice = 'Could not save: $error';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _target = target;
      _busy = false;
    });
    // Fire-and-forget: the coordinator reruns its pass in the background, and
    // a failure there is reported by its own status line, not as a save error.
    unawaited(
      ref
          .read(smbUploadCoordinatorProvider)
          .targetChanged()
          .catchError((Object _) {}),
    );
    _showMessage('Saved');
  }

  Future<String?> _readPassword(SmbUploadSettings store) async {
    try {
      return await store.readPassword();
    } catch (_) {
      return null;
    }
  }

  void _showMessage(String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    final draft = _draft(enabled: true);
    if (!draft.isComplete) {
      setState(() => _notice = _badAddress);
      return;
    }
    setState(() {
      _busy = true;
      _notice = null;
    });
    final failure = await ref
        .read(smbUploaderProvider)
        .probe(target: draft, password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = failure == null ? 'Connected' : _failureText(failure);
    });
  }

  /// The share's own text for the rarer failures; the common ones get a
  /// phrasing the user can act on.
  static String _failureText(SmbUploadFailed failure) {
    return switch (failure.kind) {
      SmbFailureKind.auth => 'Wrong user name or password',
      SmbFailureKind.notFound => 'Share or folder not found',
      SmbFailureKind.accessDenied => 'No permission to write there',
      SmbFailureKind.network => "Can't reach the server",
      SmbFailureKind.noSpace => 'The share is full',
      _ => failure.message,
    };
  }

  /// Field-level error text instead of a shared notice line: the expected
  /// address shape stays visible as the hint while the user fixes it.
  Widget _field({
    required String keyName,
    required String label,
    required TextEditingController controller,
    bool obscure = false,
  }) {
    final bad = _addressRejected && keyName == 'address';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      // No hintText here on purpose: TvTextField paints the hint as plain
      // text while the field is empty, which would double-count the address
      // string wherever a test counts how often it appears.
      child: TvTextField(
        key: Key('smb-$keyName'),
        controller: controller,
        labelText: label,
        errorText: bad ? _badAddress : null,
        obscureText: obscure,
        onChanged: (_) => setState(() {
          _notice = null;
          _addressRejected = false;
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    if (target == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const Key('smb-enabled'),
          title: const Text('Copy recordings to a network share (SMB)'),
          subtitle: Text(
            target.displayAddress.isEmpty ? 'Off' : target.displayAddress,
          ),
          value: target.enabled,
          onChanged: (on) {
            if (on) {
              setState(() => _target = target.copyWith(enabled: true));
            } else {
              // Switching off is a decision, not a draft: store it at once.
              unawaited(_save(target.copyWith(enabled: false)));
            }
          },
        ),
        if (target.enabled) ..._form(),
      ],
    );
  }

  List<Widget> _form() {
    return [
      _field(keyName: 'address', label: 'Share address', controller: _address),
      _field(keyName: 'user', label: 'User name (optional)', controller: _user),
      _field(
        keyName: 'password',
        label: 'Password',
        controller: _password,
        obscure: true,
      ),
      _field(
        keyName: 'domain',
        label: 'Domain (optional)',
        controller: _domain,
      ),
      SwitchListTile(
        key: const Key('smb-delete-local'),
        title: const Text('Delete the copy on this device after upload'),
        value: _deleteLocal,
        onChanged: (value) => setState(() => _deleteLocal = value),
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      if (_notice != null)
        Padding(
          key: const Key('smb-notice'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(_notice!),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            OutlinedButton(
              key: const Key('smb-test'),
              onPressed: () => unawaited(_testConnection()),
              child: const Text('Test connection'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('smb-save'),
              onPressed: _saveFromForm,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
      const _SmbStatusLine(),
    ];
  }
}

/// The coordinator's status line: what is uploading now, or how the last run
/// ended. Renders nothing while there is nothing to report.
class _SmbStatusLine extends ConsumerWidget {
  const _SmbStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(smbUploadStatusProvider);
    final text = _textOf(status);
    if (text == null) return const SizedBox.shrink();
    return Padding(
      key: const Key('smb-status'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(text),
    );
  }

  static String? _textOf(SmbUploadStatus status) {
    if (status.phase == SmbUploadPhase.uploading) {
      return 'Uploading ${status.currentName ?? ''} · ${status.percent}%';
    }
    if (status.phase != SmbUploadPhase.idle) return null;
    final failure = status.lastFailure;
    if (failure != null) {
      return 'Last upload failed: ${status.lastMessage ?? failure.name}';
    }
    final uploaded = status.lastUploadedName;
    return uploaded == null ? null : 'Last uploaded: $uploaded';
  }
}
