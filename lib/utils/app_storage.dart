import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'platform_util.dart';

/// Where the app is actually allowed to write.
///
/// On a PHYSICAL Apple TV, `Documents/` and `Library/Application Support/` are
/// read-only — the tvOS sandbox only accepts writes to `Library/Caches` and
/// `tmp`. The tvOS SIMULATOR permits both, which is why this never surfaced
/// until the app ran on real hardware: the sqflite database silently failed to
/// open ("error opening!: 14"), every preference fell back to its default, and
/// the UI came up unreadable with no catalogs and no images.
///
/// Everywhere else these keep their platform-standard meaning, so call sites
/// don't need to care which platform they're on.
///
/// Caches is not a promise: tvOS may purge it under storage pressure. That is
/// the correct trade for a TV box (the catalog DB is a rebuildable cache), but
/// it means nothing here should be treated as durable user data.
class AppStorage {
  AppStorage._();

  static Directory? _documents;
  static Directory? _support;
  static Directory? _cache;

  @visibleForTesting
  static void debugOverride({
    Directory? documents,
    Directory? support,
    Directory? cache,
  }) {
    _documents = documents;
    _support = support;
    _cache = cache;
  }

  @visibleForTesting
  static void debugReset() {
    _documents = null;
    _support = null;
    _cache = null;
  }

  /// Replaces `getApplicationDocumentsDirectory()`.
  static Future<Directory> documents() async =>
      _documents ??= PlatformUtil.isTvOS
      ? await getApplicationCacheDirectory()
      : await getApplicationDocumentsDirectory();

  /// Replaces `getApplicationSupportDirectory()`.
  static Future<Directory> support() async => _support ??= PlatformUtil.isTvOS
      ? await getApplicationCacheDirectory()
      : await getApplicationSupportDirectory();

  static Future<Directory> cache() async =>
      _cache ??= await getApplicationCacheDirectory();
}
