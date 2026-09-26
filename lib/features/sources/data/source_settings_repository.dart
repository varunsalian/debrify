import '../models/source_presentation_settings.dart';

abstract interface class SourceSettingsRepository {
  bool get isCurrent;
  Future<SourcePrioritySettings> loadPriority();
  Future<({bool text, bool logos})> loadAppearance();
}
