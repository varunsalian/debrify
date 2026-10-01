import '../../../models/source_appearance.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/source_appearance_preferences.dart';
import '../../../services/source_priority.dart';
import '../../../services/storage_service.dart';
import '../models/source_presentation_settings.dart';
import '../models/sources_session.dart';
import 'source_settings_repository.dart';

class StoredSourceSettingsRepository implements SourceSettingsRepository {
  const StoredSourceSettingsRepository(this.session);
  final SourcesSession session;

  @override
  bool get isCurrent => session.owner == ProfileSessionMemory.captureOwner();

  Future<T> _read<T>(Future<T> Function() read) {
    final scope = session.owner.scope;
    return scope == null
        ? read()
        : ProfileRuntime.withCapturedScope(scope, read);
  }

  @override
  Future<SourcePrioritySettings> loadPriority() async {
    if (!isCurrent) return SourcePrioritySettings();
    return _read(() async {
      final rules = await StorageService.getQuickPlayRules(
        isMovie: !session.selection.isSeries,
      );
      if (!isCurrent) return SourcePrioritySettings();
      final aliases = await SourcePriority.sourceAliases();
      if (!isCurrent) return SourcePrioritySettings();
      final providers = await SourcePriority.providers();
      if (!isCurrent) return SourcePrioritySettings();
      return SourcePrioritySettings(
        providers: [
          for (final provider in SourcePriority.orderedProviders(
            providers,
            rules.sourcePriority,
          ))
            provider.key,
        ],
        aliases: aliases,
      );
    });
  }

  @override
  Future<SourceAppearance> loadAppearance() =>
      readSourceAppearance(session.owner);
}
