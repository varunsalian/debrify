import '../models/stremio_addon.dart';
import 'stremio_service.dart';
import 'tmdb_metadata_repository.dart';

/// Hydrates a selected TMDB search result before opening IMDb-keyed details.
/// Network failure is not equivalent to a title genuinely lacking an IMDb ID.
class MetadataTitleService {
  MetadataTitleService({
    TmdbMetadataRepository? repository,
    Future<List<StremioAddon>> Function()? addons,
    Future<String?> Function()? preference,
  }) : repository = repository ?? TmdbMetadataRepository.instance,
       _addons = addons ?? StremioService.instance.getEnabledAddons,
       _preference =
           preference ?? StremioService.instance.getMetadataProviderPreference;

  static final instance = MetadataTitleService();
  final TmdbMetadataRepository repository;
  final Future<List<StremioAddon>> Function() _addons;
  final Future<String?> Function() _preference;

  Future<StremioMeta> resolve(StremioMeta item) async {
    var selected = item;
    if (item.id.startsWith('tmdb:') && item.effectiveImdbId == null) {
      final identity = await repository.identify(item);
      if (identity == null) {
        throw const TmdbMetadataException('Invalid title identity.');
      }
      final data = await repository.get(
        '${identity.type}/${identity.id}/external_ids',
      );
      if (!data.containsKey('imdb_id')) {
        throw const TmdbMetadataException(
          'Title identity response was incomplete.',
        );
      }
      final imdb = data['imdb_id'];
      if (imdb != null && imdb != '') {
        if (imdb is! String || !RegExp(r'^tt\d+$').hasMatch(imdb)) {
          throw const TmdbMetadataException('Invalid IMDb identity.');
        }
        selected = StremioMeta.fromJson({
          ...item.toJson(),
          'id': imdb,
          'imdb_id': imdb,
        });
      }
    }
    if (selected.effectiveImdbId == null && !selected.id.startsWith('tt')) {
      return selected;
    }
    // Addon discovery is optional: Trakt can still supply episodes when
    // no installed metadata addon accepts this title's ID.
    try {
      final candidates = (await _addons())
          .where(
            (a) =>
                a.enabled &&
                a.baseUrl.isNotEmpty &&
                a.resources.contains('meta') &&
                (a.types.isEmpty || a.types.contains(selected.type)) &&
                a.supportsContentId(selected.id),
          )
          .toList();
      final ordered = StremioService.metadataCandidatesForPreference(
        candidates,
        await _preference(),
      );
      if (ordered.isNotEmpty) {
        selected = selected.withSourceAddon(ordered.first);
      }
    } catch (_) {}
    return selected;
  }
}
