import '../../../models/torrent.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/source_priority.dart';
import '../../../services/stremio_service.dart';
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
