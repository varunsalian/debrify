// Composition for "Recording location & timing": binds the platform folder
// pickers to the recording-output settings page so neither the page nor the
// recordings hub imports a native service.

import 'dart:io';

import 'package:debrify/features/recording_output/models/recording_output_settings.dart';
import 'package:debrify/features/recording_output/presentation/recording_output_settings_page.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Whether this platform records at all (Android and desktops).
bool get recordingOutputSettingsAvailable =>
    Platform.isAndroid ||
    Platform.isWindows ||
    Platform.isLinux ||
    Platform.isMacOS;

/// Pushes the settings page. Folder choice is offered where a picked folder
/// is writable: the Android system picker, and the Windows/Linux directory
/// picker. macOS keeps the default folder (its sandbox grants picked folders
/// read-only), but still gets padding and the SMB copy.
Future<void> openRecordingOutputSettings(BuildContext context) {
  final android = Platform.isAndroid;
  final RecordingFolderPick? picker = android
      ? _pickAndroidFolder
      : (Platform.isWindows || Platform.isLinux)
      ? _pickDesktopFolder
      : null;
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RecordingOutputSettingsPage(
        platform: android
            ? RecordingPlatform.android
            : RecordingPlatform.desktop,
        folderPicker: picker,
      ),
    ),
  );
}

Future<({String? treeUri, String? displayName, String? path})?>
_pickAndroidFolder() async {
  final picked = await AndroidNativeDownloader.pickDownloadDirectory();
  final tree = picked?['treeUri'] as String?;
  if (tree == null || tree.isEmpty) return null;
  return (
    treeUri: tree,
    displayName: picked?['displayName'] as String?,
    path: null,
  );
}

Future<({String? treeUri, String? displayName, String? path})?>
_pickDesktopFolder() async {
  final path = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'Save recordings to',
  );
  if (path == null || path.isEmpty) return null;
  // Refuse folders we cannot write, rather than failing the first recording.
  try {
    final probe = File('$path${Platform.pathSeparator}.debrify_write_probe');
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
  } catch (_) {
    return null;
  }
  return (treeUri: null, displayName: null, path: path);
}
