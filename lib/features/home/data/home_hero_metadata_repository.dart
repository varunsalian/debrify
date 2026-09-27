import '../../../models/metadata_preferences.dart';
import '../../../models/metadata_presentation.dart';
import '../../../models/stremio_addon.dart';

/// Existing metadata services, injected without UI or provider dependencies.
class HomeHeroMetadataRepository {
  const HomeHeroMetadataRepository({
    required this.readPreferences,
    required this.fetchDetails,
    required this.present,
  });

  /// Returns null when unavailable or when the request is no longer current,
  /// matching the existing background-preferences service contract.
  final Future<MetadataPreferences?> Function(bool Function() current)
  readPreferences;
  final Future<StremioMeta?> Function(String imdbId, String type) fetchDetails;
  final Future<MetadataPresentation> Function(
    StremioMeta item,
    MetadataPreferences preferences,
    bool Function() current,
  )
  present;
}
