// Opens the active profile's share for a recording that should be written
// there directly. The share, its login and the "record straight to the share"
// choice belong to a profile, so a capture owned by another profile (a
// schedule firing while someone else is signed in) never uses them: it
// records locally and its owner's upload copies it later.

import 'package:flutter/foundation.dart';

import '../application/smb_contracts.dart';
import '../application/smb_direct_writer.dart';
import 'active_recording_profile.dart';
import 'dart_smb2_connector.dart';
import 'smb_settings_store.dart';

/// A writer on the share for [fileName], or null when the recording should
/// go to this device: direct recording is off or unconfigured, [ownerProfileId]
/// is not the active profile, or the share cannot be reached right now.
Future<SmbDirectWriter?> openSmbDirectRecording({
  required String fileName,
  required String ownerProfileId,
  SmbConnector connector = const DartSmb2Connector(),
  SmbSettingsStore? store,
}) async {
  if (activeRecordingProfileId() != ownerProfileId) return null;
  try {
    final settings = store ?? SmbSettingsStore();
    final target = await settings.readTarget();
    if (!target.writesDirect) return null;
    final password = await settings.readPassword();
    // The reads above follow the active profile: one that took over while
    // they ran must not lend this capture its share and login.
    if (activeRecordingProfileId() != ownerProfileId) return null;
    return await SmbDirectWriter.open(
      connector: connector,
      target: target,
      password: password,
      fileName: fileName,
    );
  } catch (error) {
    debugPrint('Recording: share unavailable, recording locally ($error)');
    return null;
  }
}
