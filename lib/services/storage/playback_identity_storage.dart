import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/media_identity.dart';

final class PlaybackIdentityStorage {
  const PlaybackIdentityStorage._();

  /// Save playback state for series content
  // Shared within lib/services/storage/.
  static bool requiresExactProgressIdentity(String? id) =>
      CustomSeriesIdentity.isCustom(id) || MediaIdentity.isNative(id);

  // Shared within lib/services/storage/.
  static String seriesProgressKey(String title, String? id) =>
      (requiresExactProgressIdentity(id) || (id?.startsWith('medialibrary:') ?? false))
      ? 'series_$id'
      : 'series_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
}
