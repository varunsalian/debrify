import 'metadata_preferences.dart';
import 'stremio_addon.dart';

class MetadataPresentation {
  const MetadataPresentation(
    this.item, {
    this.unavailable = const {},
    this.retryable = false,
  });
  final bool retryable;
  final StremioMeta item;
  final Set<MetadataCategory> unavailable;
}
