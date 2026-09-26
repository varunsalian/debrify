import '../../../models/cinema_source_provider.dart';
import '../../../models/torrent.dart';
import '../../../models/iptv_source_result.dart';
import '../../../services/source_priority.dart';
import '../../../models/addon_search_status.dart';
import '../models/source_provider_option.dart';

class SourceProviderProjection {
  SourceProviderProjection({
    required List<SourceProviderOption> options,
    required Map<String, AddonSearchStatus> retries,
    required this.showAll,
    required this.visible,
  }) : options = List.unmodifiable(options),
       retries = Map.unmodifiable(retries);

  final List<SourceProviderOption> options;
  final Map<String, AddonSearchStatus> retries;
  final bool showAll;
  final bool visible;
}

bool sourceStatusActionable(AddonSearchStatus status) =>
    status.failed || status.count == 0;

/// Compact-toolbar warnings, in their original server-then-IPTV display order.
List<String> sourceToolbarMessages({
  required List<AddonSearchStatus> statuses,
  required List<IptvSourceResult> iptv,
  required String? selectedKey,
}) => List.unmodifiable([
  for (final entry in sourceMediaServerMessages(statuses).entries)
    if (selectedKey == null || selectedKey == entry.key) entry.value,
  for (final source in iptv)
    if (source.retryableFailure &&
        (selectedKey == null || selectedKey == source.key))
      'IPTV · ${source.name}: ${source.message}',
]);

String sourceProviderLabel(
  String source, {
  required List<IptvSourceResult> iptv,
}) {
  for (final entry in iptv) {
    if (entry.key == source) return 'IPTV · ${entry.name}';
  }
  final value = source.startsWith('stremio:') ? source.substring(8) : source;
  return value.isEmpty ? source : value[0].toUpperCase() + value.substring(1);
}

/// Preserves source alias grouping, status label precedence and retry identity.
/// This projection performs no IO and does not own the underlying search state.
SourceProviderProjection projectSourceProviders({
  required List<Torrent> torrents,
  required List<AddonSearchStatus> statuses,
  required List<IptvSourceResult> iptv,
  required List<String> priority,
  required Map<String, String> aliases,
  required Set<String> retrying,
}) {
  final sources = <String>{
    for (final t in torrents)
      if (t.source.isNotEmpty) t.source,
  };
  final labelsByKey = <String, String>{
    for (final status in statuses) status.sourceKey: status.name,
  };
  final sourceByKey = <String, String>{
    for (final source in sources.toList()..sort())
      SourcePriority.keyForSource(source, aliases: aliases): source,
    for (final source in iptv) source.key: source.key,
  };
  for (final torrent in torrents) {
    final key = SourcePriority.keyForSource(torrent.source, aliases: aliases);
    labelsByKey.putIfAbsent(
      key,
      () =>
          torrent.addonDisplayName ??
          sourceProviderLabel(torrent.source, iptv: iptv),
    );
  }
  for (final source in iptv) {
    labelsByKey[source.key] = 'IPTV · ${source.name}';
  }
  final retryByKey = <String, AddonSearchStatus>{
    for (final status in statuses)
      if (sourceStatusActionable(status) &&
          !sourceByKey.containsKey(status.sourceKey))
        status.sourceKey: status,
  };
  final providerKeys = <String>[
    ...sourceByKey.keys,
    for (final key in retryByKey.keys)
      if (!sourceByKey.containsKey(key)) key,
  ];
  final sortedKeys = SourcePriority.orderBy(
    providerKeys,
    (key) => key,
    priority,
    aliases: aliases,
  );

  return SourceProviderProjection(
    options: [
      for (final key in sortedKeys)
        if (retryByKey[key] case final status?)
          SourceProviderOption(
            key: key,
            label: status.name,
            retryable: true,
            failed: status.failed,
            retrying: retrying.contains(status.requestKey),
          )
        else if (sourceByKey[key] case final source?)
          SourceProviderOption(
            key: key,
            label: labelsByKey[key] ?? sourceProviderLabel(source, iptv: iptv),
          ),
    ],
    retries: retryByKey,
    showAll: sourceByKey.isNotEmpty,
    visible:
        sortedKeys.length > 1 ||
        retryByKey.isNotEmpty ||
        iptv.any((source) => source.retryableFailure),
  );
}

Map<String, String> sourceMediaServerMessages(
  List<AddonSearchStatus> statuses,
) => Map.unmodifiable({
  for (final status in statuses)
    if (status.sourceKey.startsWith('mediaserver:') && status.error != null)
      status.sourceKey: status.error!,
});

/// Cinema retains zero-count groups and aggregates flags across configurations.
List<CinemaSourceProvider> projectCinemaSourceProviders({
  required List<Torrent> torrents,
  required List<AddonSearchStatus> statuses,
  required List<IptvSourceResult> iptv,
  required List<String> priority,
  required Map<String, String> aliases,
  required Set<String> retrying,
}) {
  final messages = sourceMediaServerMessages(statuses);
  final counts = <String, int>{};
  final names = <String, String>{};
  for (final status in statuses) {
    names.putIfAbsent(status.sourceKey, () => status.name);
  }
  for (final t in torrents) {
    final key = SourcePriority.keyForSource(t.source, aliases: aliases);
    counts[key] = (counts[key] ?? 0) + 1;
    names.putIfAbsent(
      key,
      () => t.addonDisplayName ?? sourceProviderLabel(t.source, iptv: iptv),
    );
  }
  for (final source in iptv) {
    names[source.key] = 'IPTV · ${source.name}';
  }
  final iptvMessages = {
    for (final source in iptv)
      if (source.retryableFailure) source.key: source.message,
  };
  final keys = SourcePriority.orderBy(
    names.keys.toList()..sort(),
    (key) => key,
    priority,
    aliases: aliases,
  );
  return List.unmodifiable([
    CinemaSourceProvider(
      id: null,
      label: 'All sources',
      count: torrents.length,
    ),
    for (final key in keys)
      CinemaSourceProvider(
        id: key,
        label: names[key]!.isEmpty ? 'Other sources' : names[key]!,
        count: counts[key] ?? 0,
        message: iptvMessages[key] ?? messages[key],
        failed: statuses.any((s) => s.sourceKey == key && s.failed),
        loading: statuses.any(
          (s) => s.sourceKey == key && retrying.contains(s.requestKey),
        ),
      ),
  ]);
}
