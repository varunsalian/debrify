import 'package:debrify/features/recording_output/models/share_recording.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_owners.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_sections.dart';
import 'package:flutter/material.dart';

class RecordingsHubDependencies {
  RecordingsHubDependencies({
    required this.owners,
    required this.context,
    required this.mounted,
    required this.setState,
    required this.sections,
    this.openOutputSettings,
    this.share,
  });
  final RecordingsHubOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final RecordingsHubSections Function() sections;

  /// Opens "Recording location & timing" (folder, padding, SMB copy); null
  /// where recording settings are unavailable. Wired by the screen facade.
  final Future<void> Function()? openOutputSettings;

  /// The profile's network share; null where recording is unavailable.
  final RecordingsHubShare? share;
}

/// What the hub needs from the network share, wired by the screen facade.
class RecordingsHubShare {
  const RecordingsHubShare({
    required this.load,
    required this.streamUrl,
    required this.delete,
    required this.openSettings,
  });

  /// The share's recordings; null when no share is set up.
  final Future<ShareLibrary?> Function() load;

  /// A URL the player can stream a share recording from.
  final Future<Uri> Function(ShareRecording recording) streamUrl;

  /// Throws when the share refuses.
  final Future<void> Function(ShareRecording recording) delete;
  final Future<void> Function() openSettings;
}
