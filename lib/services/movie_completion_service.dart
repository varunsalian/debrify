import '../models/media_identity.dart';
import 'tracking_source_policy.dart';
import 'storage_service.dart';
import 'trakt/trakt_service.dart';
import 'simkl/simkl_service.dart';
import 'mdblist/mdblist_service.dart';

class MovieCompletionService {
  static Future<bool> load(
    String imdbId, {
    TrackingSourcePolicy? policy,
    Future<bool> Function(TrackingSource)? read,
  }) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final selected = (policy ?? await TrackingSourcePolicy.load()).forContent(imdbId);
    final results = await Future.wait([
      for (final source in TrackingSource.values)
        if (selected.progressFrom(source))
          (() async {
            try {
              return await (read ?? (s) => _read(imdbId, s))(source);
            } catch (_) {
              return false;
            }
          })(),
    ]);
    return results.any((completed) => completed);
  }

  static Future<bool> _read(String id, TrackingSource source) async {
    switch (source) {
      case TrackingSource.local:
        return StorageService.isMovieFinished(id);
      case TrackingSource.trakt:
        final service = TraktService.instance;
        if (!await service.isAuthenticated()) return false;
        return (await service.fetchTitleStatus(id, 'movie'))?.watched == true;
      case TrackingSource.simkl:
        final service = SimklService.instance;
        if (!await service.isAuthenticated()) return false;
        return (await service.fetchTitleStatus(id, contentType: 'movie'))?.currentStatus ==
            'completed';
      case TrackingSource.mdblist:
        final service = MdblistService.instance;
        if (!await service.isAuthenticated()) return false;
        return (await service.fetchTitleStatus(id, 'movie'))?.watched == true;
    }
  }
}
