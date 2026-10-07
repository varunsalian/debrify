import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_data.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_dependencies.dart';
import 'package:debrify/features/recordings/presentation/legacy_recordings/recordings_hub_format.dart';

class RecordingsHubSections {
  RecordingsHubSections(RecordingsHubDependencies deps)
    : data = RecordingsHubData(deps),
      format = RecordingsHubFormat(deps);
  final RecordingsHubData data;
  final RecordingsHubFormat format;
}
