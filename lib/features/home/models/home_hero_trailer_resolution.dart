import '../../../services/youtube_service.dart' show YoutubeResolvedStreams;

/// A stale completion must leave the current loading indicator alone, while
/// unavailable preferences/streams follow the caller's guarded failure path.
class HomeHeroTrailerResolution {
  const HomeHeroTrailerResolution.ready(YoutubeResolvedStreams value)
    : streams = value,
      retired = false;
  const HomeHeroTrailerResolution.unavailable()
    : streams = null,
      retired = false;
  const HomeHeroTrailerResolution.retired() : streams = null, retired = true;

  final YoutubeResolvedStreams? streams;
  final bool retired;
}
