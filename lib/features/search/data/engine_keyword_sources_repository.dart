import '../../../services/engine/dynamic_engine.dart';
import '../../../services/engine/settings_manager.dart';
import '../../../services/profiles/profile_preferences.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/keyword_source.dart';
import 'keyword_sources_repository.dart';

class EngineKeywordSourcesRepository implements KeywordSourcesRepository {
  final ProfileSessionOwner owner;
  final SettingsManager settings;
  final Future<List<DynamicEngine>> Function() engines;

  const EngineKeywordSourcesRepository({
    required this.owner,
    required this.settings,
    required this.engines,
  });

  @override
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  Future<T> _inScope<T>(Future<T> Function() action) {
    final scope = owner.scope;
    return scope == null
        ? action()
        : ProfileRuntime.withCapturedScope(scope, action);
  }

  @override
  Future<List<KeywordSource>> load() async {
    if (!isCurrent) return const [];
    // Composition supplies the SAME combined registry + user-configured
    // indexer-manager collection used by keyword search, in the same order.
    final available = await _inScope(engines);
    final sources = <KeywordSource>[];
    for (final engine in available) {
      if (!isCurrent) return const [];
      final enabled = await _inScope(
        () => settings.getEnabled(
          engine.name,
          engine.settingsConfig.enabled?.defaultBool ?? true,
        ),
      );
      sources.add(
        KeywordSource(
          id: engine.name,
          label: engine.displayName,
          enabled: enabled,
        ),
      );
    }
    return isCurrent ? List.unmodifiable(sources) : const [];
  }

  @override
  Future<void> setEnabled(String id, bool enabled) async {
    if (!isCurrent) return;
    final prefs = await _inScope(ProfilePreferences.instance);
    if (!isCurrent) return;
    // Reuse SettingsManager's exact key normalization. As for catalog sources,
    // live-session assertions must run outside the captured read zone.
    await prefs.setBool(settings.generateKey(id, 'enabled'), enabled);
  }
}
