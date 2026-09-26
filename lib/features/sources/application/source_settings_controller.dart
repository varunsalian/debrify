import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/source_settings_repository.dart';
import '../models/source_presentation_settings.dart';
import '../models/sources_session.dart';
import 'source_seasons_dependencies.dart';
import 'source_settings_dependencies.dart';

final sourceSettingsProvider = NotifierProvider.autoDispose
    .family<
      SourceSettingsController,
      SourcePresentationSettings,
      SourcesSession
    >(SourceSettingsController.new, retry: (count, error) => null);

class SourceSettingsController extends Notifier<SourcePresentationSettings> {
  SourceSettingsController(this.session);
  final SourcesSession session;
  late SourceSettingsRepository _repository;
  int _generation = 0;

  @override
  SourcePresentationSettings build() {
    _repository = ref.watch(sourceSettingsRepositoryProvider(session));
    ref.watch(sourcesSessionActiveProvider(session));
    ref.onDispose(() => _generation++);
    return SourcePresentationSettings();
  }

  bool _accept(int generation) =>
      ref.mounted && _repository.isCurrent && generation == _generation;

  Future<void> load() async {
    if (!ref.mounted || !_repository.isCurrent) return;
    final generation = ++_generation;
    await Future.wait([_loadPriority(generation), _loadAppearance(generation)]);
  }

  Future<void> _loadPriority(int generation) async {
    try {
      final priority = await _repository.loadPriority();
      if (!_accept(generation)) return;
      state = SourcePresentationSettings(
        priority: priority,
        useAddonText: state.useAddonText,
        showAddonLogos: state.showAddonLogos,
      );
    } catch (_) {
      // Existing startup tolerates missing priority and retains incoming order.
    }
  }

  Future<void> _loadAppearance(int generation) async {
    final appearance = await _repository.loadAppearance();
    if (!_accept(generation)) return;
    state = SourcePresentationSettings(
      priority: state.priority,
      useAddonText: appearance.text,
      showAddonLogos: appearance.logos,
    );
  }
}
