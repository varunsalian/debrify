// Composition for "Recording location & timing" and the network share:
// binds the platform folder pickers to the recording-output settings page and
// the share library to the Recordings hub, so neither the pages nor the hub
// import a native service or another feature's data layer.

import 'dart:io';

import 'package:debrify/features/recording_output/data/share_library_repository.dart';
import 'package:debrify/features/recording_output/data/share_stream_server.dart';
import 'package:debrify/features/recording_output/models/recording_output_settings.dart';
import 'package:debrify/features/recording_output/presentation/network_share_settings_page.dart';
import 'package:debrify/features/recording_output/presentation/recording_output_settings_page.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
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

/// The network share as the Recordings page uses it: listed per load,
/// streamed through the loopback server, settings on their own page. Null
/// where nothing records.
RecordingsHubShare? recordingsHubShare(BuildContext Function() context) {
  final override = debugRecordingsHubShare;
  if (override != null) return override(context);
  if (!recordingOutputSettingsAvailable) return null;
  final library = ShareLibraryRepository();
  return RecordingsHubShare(
    load: library.load,
    streamUrl: ShareStreamServer.instance.urlFor,
    delete: library.delete,
    openSettings: () => openNetworkShareSettings(context()),
  );
}

/// Replaces the share [recordingsHubShare] returns, for tests.
@visibleForTesting
RecordingsHubShare? Function(BuildContext Function() context)?
debugRecordingsHubShare;

/// Pushes "Network share": where recordings are written to or copied to.
Future<void> openNetworkShareSettings(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NetworkShareSettingsPage()),
    );

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
