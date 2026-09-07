import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Shared image disk cache for poster/thumbnail-heavy surfaces.
///
/// `CachedNetworkImage` without an explicit manager uses `DefaultCacheManager`,
/// which caps the store at 200 objects (LRU). A single TV browsing session —
/// Home rows, Discover boards, backdrops — churns straight through that, so by
/// the time a series page is reopened its episode stills have been evicted and
/// every one re-downloads. Pass this manager as `cacheManager:` at image-heavy
/// call sites so artwork survives a browsing session.
///
/// Note: images cached here live under their own cache key, separate from the
/// default manager's store — a URL cached by one is not visible to the other.
class DebrifyImageCache {
  DebrifyImageCache._();

  /// Runs after the first frame, including stores not visited this session.
  /// Keep the legacy default store in the repair sweep as it held artwork too.
  static void scheduleMaintenance() {
    manager.store.scheduleCleanup();
    iptvLogos.store.scheduleCleanup();
    DefaultCacheManager().store.scheduleCleanup();
  }

  static final CacheManager manager = CacheManager(
    Config(
      'debrifyImageCache',
      // Byte high-water mark; background LRU cleanup trims to 180 MiB.
      maxCacheBytes: 200 * 1024 * 1024,
      maxNrOfCacheObjects: 1000,
      stalePeriod: const Duration(days: 30),
    ),
  );

  /// Separate store for IPTV channel logos: tiny files, huge cardinality.
  /// They used to ride the DEFAULT manager's 200-object store, so scrolling
  /// a big guide re-downloaded every logo continuously; and sharing
  /// [manager] instead would let one 50k-channel scroll evict every Home
  /// backdrop and poster. A dedicated store keeps each surface's churn to
  /// itself. The separate 30 MiB budget trims to 27 MiB when exceeded.
  static final CacheManager iptvLogos = CacheManager(
    Config(
      'debrifyIptvLogoCache',
      maxNrOfCacheObjects: 2000,
      maxCacheBytes: 30 * 1024 * 1024,
      stalePeriod: const Duration(days: 30),
    ),
  );
}
