
class IptvPortal {
  final String url;
  final String username;
  final String password;
  final String source;

  const IptvPortal({
    required this.url,
    required this.username,
    required this.password,
    this.source = '',
  });

  String get key => '$url|$username|$password'.toLowerCase();
  String get credKey => '$username|$password'.toLowerCase();

  Map<String, dynamic> toJson() => {
        'url': url,
        'username': username,
        'password': password,
        'source': source,
      };

  factory IptvPortal.fromJson(Map<String, dynamic> j) => IptvPortal(
        url: j['url'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        source: j['source'] as String? ?? '',
      );
}

class VerifiedPortal {
  final IptvPortal portal;
  final String name;
  final String expiry;
  final String maxConnections;
  final String activeConnections;

  const VerifiedPortal({
    required this.portal,
    required this.name,
    required this.expiry,
    required this.maxConnections,
    required this.activeConnections,
  });

  String get key => portal.key;
  String get credKey => portal.credKey;
}

class IptvCategory {
  final String id;
  final String name;
  const IptvCategory({required this.id, required this.name});
}

enum IptvSection { live, vod, series }

class IptvStream {
  final String streamId;
  final String name;
  final String icon;
  final String categoryId;
  final String containerExt;
  final String kind;
  final String epgChannelId;

  const IptvStream({
    required this.streamId,
    required this.name,
    required this.icon,
    required this.categoryId,
    required this.containerExt,
    required this.kind,
    this.epgChannelId = '',
  });
}

class EpgEntry {
  final String title;
  final String description;
  final DateTime start;
  final DateTime stop;
  const EpgEntry({
    required this.title,
    required this.description,
    required this.start,
    required this.stop,
  });

  bool get isNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(stop);
  }
}

class IptvEpisode {
  final String id;
  final String title;
  final String containerExt;
  final int season;
  final int episode;
  final String plot;
  final String image;

  const IptvEpisode({
    required this.id,
    required this.title,
    required this.containerExt,
    required this.season,
    required this.episode,
    required this.plot,
    required this.image,
  });
}

class ChannelHit {
  final VerifiedPortal portal;
  final IptvStream stream;
  final String streamUrl;

  const ChannelHit({
    required this.portal,
    required this.stream,
    required this.streamUrl,
  });
}

class ScrapePage {
  final List<IptvPortal> portals;
  final String? nextAfter;
  const ScrapePage({required this.portals, this.nextAfter});
  bool get hasMore => nextAfter != null && nextAfter!.isNotEmpty;
}

class AliveSnapshot {
  final int checkedAt;
  final Set<String> aliveIds;
  const AliveSnapshot({required this.checkedAt, required this.aliveIds});
}

class StoredHit {
  final String portalUrl;
  final String portalUser;
  final String portalPass;
  final String portalName;
  final String streamId;
  final String streamName;
  final String streamIcon;
  final String streamCategoryId;
  final String streamContainerExt;
  final String streamKind;
  final String streamUrl;

  const StoredHit({
    required this.portalUrl,
    required this.portalUser,
    required this.portalPass,
    required this.portalName,
    required this.streamId,
    required this.streamName,
    required this.streamIcon,
    required this.streamCategoryId,
    required this.streamContainerExt,
    required this.streamKind,
    required this.streamUrl,
  });
}
