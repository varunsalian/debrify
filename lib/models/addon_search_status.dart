/// One addon's outcome for a single stream search — lets the source provider
/// row retain retry controls for addons that failed or returned nothing (the
/// count maps alone lose zero-count addons once counts are rebuilt from the
/// final rows).
///
/// [sourceKey] matches `Torrent.source` and identifies one configured addon;
/// [count] is the addon's RAW stream count before cross-addon dedupe, so
/// "returned something that deduped away" still reads as activity.
class AddonSearchStatus {
  final String addonId;
  final String? addonKey;
  final String name;
  final String sourceKey;
  final int count;
  final String? error;

  const AddonSearchStatus({
    required this.addonId,
    this.addonKey,
    required this.name,
    required this.sourceKey,
    required this.count,
    this.error,
  });

  bool get failed => error != null;
  String get requestKey => addonKey ?? addonId;

  AddonSearchStatus withResult(int count) => AddonSearchStatus(
    addonId: addonId,
    addonKey: addonKey,
    name: name,
    sourceKey: sourceKey,
    count: count,
  );
}
