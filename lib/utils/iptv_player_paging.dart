/// Chooses the start offset for a native-player IPTV zap page.
///
/// Anchored pages keep the selected channel near the middle where possible.
/// Explicit offsets may point at the final item because they are used for
/// forward/backward page requests, while [fromEnd] always returns a full final
/// page when the catalog is larger than [limit].
int iptvPlayerZapPageOffset({
  required int total,
  required int limit,
  int requestedOffset = 0,
  int? anchorIndex,
  bool fromEnd = false,
}) {
  if (total <= 0) return 0;

  final safeLimit = limit.clamp(1, 1 << 30);
  final lastFullPage = (total - safeLimit).clamp(0, 1 << 30);
  if (fromEnd) return lastFullPage;
  if (anchorIndex != null) {
    return (anchorIndex - safeLimit ~/ 2).clamp(0, lastFullPage);
  }
  return requestedOffset.clamp(0, total - 1);
}
