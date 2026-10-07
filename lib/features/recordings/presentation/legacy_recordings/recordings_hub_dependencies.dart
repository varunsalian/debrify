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
  });
  final RecordingsHubOwners owners;
  final BuildContext Function() context;
  final bool Function() mounted;
  final void Function(VoidCallback) setState;
  final RecordingsHubSections Function() sections;
}
