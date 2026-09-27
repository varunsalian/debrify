import '../../../core/metadata/metadata_presentation_cache.dart';
import '../../../models/metadata_preferences.dart';
import '../../../models/metadata_presentation.dart';
import '../../../models/stremio_addon.dart';
import '../models/home_card_metadata.dart';

class HomeCardMetadataRepository {
  HomeCardMetadataRepository({
    required this.epoch,
    required this.cache,
    required this.isCurrent,
    required this.readPreferences,
    required this.present,
    required this.recordReady,
  });

  final HomeCardMetadataEpoch epoch;
  final MetadataPresentationCache cache;
  final bool Function() isCurrent;
  final Future<MetadataPreferences> Function() readPreferences;
  final Future<MetadataPresentation> Function(
    StremioMeta item,
    MetadataPreferences preferences,
    bool Function() relevant,
  )
  present;
  final void Function(HomeCardMetadataDiagnostic diagnostic) recordReady;

  MetadataPresentationCacheEntry? prepareAndTake(
    StremioMeta original,
    MetadataPreferences preferences,
  ) {
    if (!isCurrent()) return null;
    cache.prepare(
      scope: epoch.owner.scope,
      revision: epoch.revision,
      preferences: preferences,
    );
    return cache.take(original);
  }

  void accept(
    StremioMeta original,
    MetadataPresentation presentation,
    HomeCardMetadataDiagnostic diagnostic,
  ) {
    if (!isCurrent()) return;
    recordReady(diagnostic);
    if (!isCurrent()) return;
    cache.store(original, presentation);
  }
}
