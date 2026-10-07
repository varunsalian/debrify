import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_actions.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_layout.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_scheduling.dart';

class RecordingsHubSections {
  RecordingsHubSections(RecordingsHubDependencies deps)
    : data = RecordingsHubData(deps),
      actions = RecordingsHubActions(deps),
      scheduling = RecordingsHubScheduling(deps),
      format = RecordingsHubFormat(deps),
      layout = RecordingsHubLayout(deps);
  final RecordingsHubData data;
  final RecordingsHubActions actions;
  final RecordingsHubScheduling scheduling;
  final RecordingsHubFormat format;
  final RecordingsHubLayout layout;
}
