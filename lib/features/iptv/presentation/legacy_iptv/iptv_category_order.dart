import 'dart:async';

import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_catalog_key.dart';
import 'package:flutter/material.dart';

class IptvCategoryOrder {
  /// Local files bypass the catalog-backed load path, but their category-list
  /// order intentionally lives in the same profile-scoped database. Opening it
  /// here makes cold loads and the first load after a profile switch reliable.
  /// The database is optional for playback: if its cache cannot be opened, the
  /// provider order is returned and the local playlist still renders.

  static Future<List<String>> applyStoredLocalCategoryOrder(
    String playlistId,
    Iterable<String> categories,
  ) async {
    final baseline = categories.toList(growable: false);
    try {
      await IptvCatalogDb.open();
    } catch (error) {
      debugPrint(
        'IPTV: local category-order database unavailable; using provider '
        'order ($error)',
      );
      return baseline;
    }
    return IptvCatalogDb.applyCategoryOrder(
      IptvCatalogKey.forLocalCategoryOrder(playlistId),
      baseline,
    );
  }
}
