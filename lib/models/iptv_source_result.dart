import 'torrent.dart';

class IptvSourceResult {
  const IptvSourceResult(
    this.key,
    this.name,
    this.message,
    this.torrents, {
    this.retryableFailure = false,
  });
  final String key;
  final String name;
  final String message;
  final List<Torrent> torrents;
  final bool retryableFailure;
}

enum IptvEpisodeResolutionStatus { resolved, missing, unavailable }

class IptvEpisodeResolution {
  const IptvEpisodeResolution(this.status, [this.source]);

  final IptvEpisodeResolutionStatus status;
  final Torrent? source;
}
