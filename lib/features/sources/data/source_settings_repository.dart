import '../../../models/source_appearance.dart';
import '../models/source_presentation_settings.dart';

abstract interface class SourceSettingsRepository {
  bool get isCurrent;
  Future<SourcePrioritySettings> loadPriority();
  Future<SourceAppearance> loadAppearance();
}
