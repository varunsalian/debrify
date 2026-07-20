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
      maxNrOfCacheObjects: 2000,
      stalePeriod: const Duration(days: 30),
    ),
  );
}
