import 'dart:io';
import 'dart:typed_data';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_dependencies.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_owners.dart';
import 'package:debrify/features/edit_profile/presentation/legacy_edit_profile/edit_profile_sections.dart';
import 'package:debrify/services/cache_scratch_cleanup.dart';
import 'package:debrify/services/profiles/profile_avatar_ingest.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditProfileAvatarPicker {
  final EditProfileDependencies _deps;
  EditProfileAvatarPicker(this._deps);
  EditProfileOwners get _owners => _deps.owners;
  EditProfileSections get _sections => _deps.sections();
  Future<void> pickAvatarImage() async {
    if (_owners.form.saving) return;
    String? pickerCopy;
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
      pickerCopy = file.path;
      if (file.size > ProfileAvatarIngest.maxInputBytes) {
        throw const ProfileAvatarRejected(
          'That image is too large to open. Choose one under 12 MB.',
        );
      }
      final bytes = await _sections.avatar._readPickedBytes(file);
      final prepared = await ProfileAvatarIngest.prepare(bytes);
      if (!_deps.mounted() || _owners.form.saving) return;
      _deps.setState(() => _owners.form.pendingAvatarBytes = prepared.bytes);
    } on ProfileAvatarRejected catch (rejected) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text(rejected.message)));
    } on PlatformException {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('The image picker is not available.')),
      );
    } catch (_) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('That image could not be opened.')),
      );
    } finally {
      await CacheScratchCleanup.releasePickerCopy(pickerCopy);
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
}
