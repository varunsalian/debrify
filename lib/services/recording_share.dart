// The share a recording is written to directly, for "saving to …" messages
// outside the recording-output feature.

import '../features/recording_output/data/smb_settings_store.dart';

/// `\\host\share\folder` when the active profile records straight to its
/// share, else null.
Future<String?> directRecordingShareLabel({SmbSettingsStore? store}) async {
  try {
    final target = await (store ?? SmbSettingsStore()).readTarget();
    return target.writesDirect ? target.displayAddress : null;
  } catch (_) {
    return null;
  }
}
