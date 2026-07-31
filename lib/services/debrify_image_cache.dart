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

  static final CacheManager manager = CacheManager(
    Config(
      'debrifyImageCache',
      // flutter_cache_manager caps object COUNT, not bytes. On TV this store
      // was reaching ~600 MB at 2000 objects because full-size backdrops
      // (~2.6 MB each) share the slots with posters. Halving the slot count
      // roughly halves the on-disk footprint — a proxy, not a hard byte cap.
      maxNrOfCacheObjects: 1000,
      stalePeriod: const Duration(days: 30),
    ),
  );

  /// Separate store for IPTV channel logos: tiny files, huge cardinality.
  /// They used to ride the DEFAULT manager's 200-object store, so scrolling
  /// a big guide re-downloaded every logo continuously; and sharing
  /// [manager] instead would let one 50k-channel scroll evict every Home
  /// backdrop and poster. A dedicated store keeps each surface's churn to
  /// itself — 2000 logos at the typical 10-50 KB is tens of MB of disk, cap.
  static final CacheManager iptvLogos = CacheManager(
    Config(
      'debrifyIptvLogoCache',
      maxNrOfCacheObjects: 2000,
      stalePeriod: const Duration(days: 30),
    ),
  );
}
