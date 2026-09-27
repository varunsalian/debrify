import '../../../services/stremio_iptv_service.dart' show StremioIptvCandidate;

/// Borrowed Stremio IPTV resolution/cache operations for a hero preview.
class HomeHeroLiveRepository {
  const HomeHeroLiveRepository({
    required this.isAddonChannel,
    required this.resolveCandidates,
    required this.invalidate,
  });

  final bool Function(String channelKey) isAddonChannel;
  final Future<List<StremioIptvCandidate>> Function(String channelKey)
  resolveCandidates;
  final void Function(String channelKey) invalidate;
}
