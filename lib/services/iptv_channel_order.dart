import 'package:flutter/foundation.dart';

import '../models/iptv_playlist.dart';

/// Stable identity for one occurrence of a channel inside a category.
///
/// IPTV playlists may legally repeat the same URL and name, so URL alone is
/// not sufficient for a reorder editor. Xtream rows use their provider stream
/// or series ID so a password rotation (which changes every playable URL) does
/// not erase the order. [occurrence] is assigned in provider order among rows
/// with the same base identity.
class IptvChannelOrderIdentity {
  const IptvChannelOrderIdentity({
    required this.url,
    required this.name,
    required this.occurrence,
  });

  final String url;
  final String name;
  final int occurrence;

  @override
  bool operator ==(Object other) =>
      other is IptvChannelOrderIdentity &&
      other.url == url &&
      other.name == name &&
      other.occurrence == occurrence;

  @override
  int get hashCode => Object.hash(url, name, occurrence);
}

class IptvChannelOrderEntry {
  const IptvChannelOrderEntry({required this.identity, required this.channel});

  final IptvChannelOrderIdentity identity;
  final IptvChannel channel;
}

/// Cross-surface invalidation for manual IPTV presentation-order changes.
///
/// The settings route is commonly pushed over a still-mounted IPTV page. A
/// single signal lets that page rebuild immediately for channel order or the
/// category list itself, without coupling either storage backend to a widget.
class IptvChannelOrderSignal {
  IptvChannelOrderSignal._();

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static IptvChannelOrderChange? latest;

  static void notifyListChanged(String listId) => _notify(
    IptvChannelOrderChange(scope: IptvChannelOrderScope.list, target: listId),
  );

  static void notifySourceChanged(String sourceId) => _notify(
    IptvChannelOrderChange(
      scope: IptvChannelOrderScope.source,
      target: sourceId,
    ),
  );

  static void notifyCatalogChanged(String catalogKey) => _notify(
    IptvChannelOrderChange(
      scope: IptvChannelOrderScope.catalog,
      target: catalogKey,
    ),
  );

  static void _notify(IptvChannelOrderChange change) {
    latest = change;
    revision.value++;
  }
}

enum IptvChannelOrderScope { list, source, catalog }

class IptvChannelOrderChange {
  const IptvChannelOrderChange({required this.scope, required this.target});

  final IptvChannelOrderScope scope;
  final String target;
}

/// The refresh-stable portion of a channel-order identity.
///
/// Xtream exposes durable numeric IDs in channel attributes; names and stream
/// URLs are mutable presentation data there. Generic M3U has no comparable
/// provider ID, so URL + name remains its safest available identity.
({String url, String name}) iptvChannelOrderIdentityBase({
  required String url,
  required String name,
  required String? contentType,
  required Map<String, String> attributes,
}) {
  final providerId = switch (contentType) {
    'live' || 'vod' => attributes['stream_id'],
    'series' => attributes['series_id'],
    _ => null,
  };
  if (providerId != null && providerId.isNotEmpty) {
    return (url: 'xtream|$contentType|$providerId', name: '');
  }
  return (url: url, name: name);
}

({String url, String name}) iptvChannelOrderIdentityBaseFor(
  IptvChannel channel,
) => iptvChannelOrderIdentityBase(
  url: channel.url,
  name: channel.name,
  contentType: channel.contentType,
  attributes: channel.attributes,
);

/// Assign duplicate occurrences in provider order for one category.
List<IptvChannelOrderEntry> iptvCategoryOrderEntries(
  Iterable<IptvChannel> channels,
  String group,
) {
  final occurrences = <(String, String), int>{};
  final entries = <IptvChannelOrderEntry>[];
  for (final channel in channels) {
    if (channel.group != group) continue;
    final base = iptvChannelOrderIdentityBaseFor(channel);
    final key = (base.url, base.name);
    final occurrence = occurrences[key] ?? 0;
    occurrences[key] = occurrence + 1;
    entries.add(
      IptvChannelOrderEntry(
        identity: IptvChannelOrderIdentity(
          url: base.url,
          name: base.name,
          occurrence: occurrence,
        ),
        channel: channel,
      ),
    );
  }
  return entries;
}
