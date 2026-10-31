// Composition for "Recording location & timing" and the network share:
// binds the platform folder pickers to the recording-output settings page and
// the share library to the Recordings hub, so neither the pages nor the hub
// import a native service or another feature's data layer.

import 'dart:io';

import 'package:debrify/features/recording_output/data/share_library_repository.dart';
import 'package:debrify/features/recording_output/data/share_stream_server.dart';
import 'package:debrify/features/recording_output/models/recording_output_settings.dart';
import 'package:debrify/features/recording_output/models/storage_volume_choice.dart';
import 'package:debrify/features/recording_output/presentation/network_share_settings_page.dart';
import 'package:debrify/features/recording_output/presentation/recording_output_settings_page.dart';
import 'package:debrify/features/recording_output/presentation/storage_drive_dialog.dart';
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
/// is writable: the Android system picker (or, on a device without one, a
/// drive chooser), and the Windows/Linux directory picker. macOS keeps the default folder (its sandbox grants picked folders
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

/// A chosen recordings folder, as [RecordingFolderPick] returns it.
typedef RecordingFolderPickResult = ({
  String? treeUri,
  String? displayName,
  String? path,
});

/// The device's folder picker, or the drive chooser where there is none.
Future<RecordingFolderPickResult?> _pickAndroidFolder(
  BuildContext context,
  RecordingOutputSettings current,
) => pickAndroidRecordingFolder(context, current);

/// The Android "Save recordings to" choice: the system picker where there
/// is one, else the drive chooser. The functions stand in for the native
/// channels in tests.
@visibleForTesting
Future<RecordingFolderPickResult?> pickAndroidRecordingFolder(
  BuildContext context,
  RecordingOutputSettings current, {
  Future<bool> Function() canPickFolders =
      AndroidNativeDownloader.canPickFolders,
  Future<RecordingFolderPickResult?> Function() systemPicker =
      _pickWithSystemPicker,
  Future<List<StorageVolumeChoice>> Function() listVolumes =
      AndroidNativeDownloader.listStorageVolumes,
}) async {
  if (await canPickFolders()) return systemPicker();
  final drives = await listVolumes();
  if (!context.mounted) return null;
  final choice = await showStorageDriveDialog(
    context,
    volumes: drives,
    currentPath: current.treeUri == null ? current.directoryPath : null,
  );
  switch (choice) {
    case StorageDriveSelected(:final volume):
      return (treeUri: null, displayName: volume.name, path: volume.path);
    case StorageDriveNetworkShare():
      if (context.mounted) await openNetworkShareSettings(context);
      return null;
    case null:
      return null;
  }
}

Future<RecordingFolderPickResult?> _pickWithSystemPicker() async {
  final picked = await AndroidNativeDownloader.pickDownloadDirectory();
  final tree = picked?['treeUri'] as String?;
  if (tree == null || tree.isEmpty) return null;
  return (
    treeUri: tree,
    displayName: picked?['displayName'] as String?,
    path: null,
  );
}

Future<RecordingFolderPickResult?> _pickDesktopFolder(
  BuildContext context,
  RecordingOutputSettings current,
) async {
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
