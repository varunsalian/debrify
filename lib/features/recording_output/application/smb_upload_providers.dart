// Composition of the SMB recording upload: binds the concrete dart_smb2
// adapter, local recording files and settings store to the uploader and the
// app-lifetime coordinator.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/dart_smb2_connector.dart';
import '../data/local_recording_files.dart';
import '../data/smb_settings_store.dart';
import 'smb_upload_coordinator.dart';
import 'smb_upload_status_notifier.dart';
import 'smb_uploader.dart';

/// False on iOS/tvOS: no recordings there, and no bundled libsmb2.
final smbUploadSupportedProvider = Provider<bool>((ref) => smbUploadSupported);

final smbSettingsStoreProvider = Provider<SmbSettingsStore>(
  (ref) => SmbSettingsStore(),
);

final smbUploaderProvider = Provider<SmbUploader>(
  (ref) => SmbUploader(
    connector: const DartSmb2Connector(),
    source: readLocalRecording,
  ),
);

/// App lifetime. Started by SmbUploadHost, stopped when the scope goes away.
final smbUploadCoordinatorProvider = Provider<SmbUploadCoordinator>((ref) {
  final status = ref.read(smbUploadStatusProvider.notifier);
  final coordinator = SmbUploadCoordinator(
    settings: ref.read(smbSettingsStoreProvider),
    uploader: ref.read(smbUploaderProvider),
    listRecordings: listLocalRecordings,
    activeUris: activeRecordingUris,
    deleteLocal: deleteLocalRecording,
    nowMs: () => DateTime.now().millisecondsSinceEpoch,
    scopeId: currentRecordingScope,
    onStatus: status.publish,
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});
