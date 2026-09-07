import 'package:flutter/material.dart';

import '../services/cloud/cloud_provider_id.dart';
import '../services/cloud/cloud_provider_presentation.dart';
import '../services/series_source_service.dart';

/// Flutter colors/icons. String identity lives on [CloudProviderId]; the
/// label/code/gradient data lives on [CloudProviderPresentation] (services)
/// and is re-exposed here so widget callers have one lookup.
///
/// Lookup rules, on purpose:
/// - [label]/[code]/[gradient]/[icon]: exact playback id (`debrid`, not `rd`)
/// - [catalogChip]/[catalogTitle]: [CloudProviderId.tryParse]; `auto` → AUTO
/// - [playlistBadge]: playlist JSON; empty → RD, `webdav` → DV, else two letters
/// - [sourceChip]: stored id (`rd`); local is `Local`, not [label]'s `On-device`
class CloudProviderChrome {
  CloudProviderChrome._();

  static String label(String provider) =>
      CloudProviderPresentation.label(provider);

  static String code(String provider) =>
      CloudProviderPresentation.code(provider);

  static List<Color> gradient(String provider) =>
      CloudProviderPresentation.gradient(provider);

  static IconData icon(String provider) {
    return switch (CloudProviderId.fromPlaybackId(provider)) {
      CloudProviderId.debrid => Icons.cloud_download_rounded,
      CloudProviderId.torbox => Icons.flash_on_rounded,
      CloudProviderId.premiumize => Icons.workspace_premium_rounded,
      CloudProviderId.alldebrid => Icons.all_inclusive_rounded,
      CloudProviderId.pikpak => Icons.cloud_circle_rounded,
      null => Icons.cloud_download_rounded,
    };
  }

  /// `auto` / unknown -> `AUTO`, not the first letter of the string.
  static String catalogChip(String provider) =>
      CloudProviderPresentation.catalogChip(provider);

  static String? catalogTitle(String provider) =>
      CloudProviderPresentation.catalogTitle(provider);

  /// Playlist card glyph. Not [catalogChip]: empty is RD, unknown is two
  /// letters, WebDAV is DV.
  static String playlistBadge(String? raw) =>
      CloudProviderPresentation.playlistBadge(raw);

  /// Bind-source chip. TorBox is blue here; playback [gradient] is purple.
  static ({String label, Color color}) sourceChip(String stored) => (
        label: _sourceLabel(stored),
        color: _sourceColor(stored),
      );

  static String _sourceLabel(String stored) {
    switch (stored) {
      case SeriesSource.localService:
        return 'Local';
      case SeriesSource.addonDirectService:
        return 'Direct addon';
      default:
        return CloudProviderId.fromStoredId(stored)?.displayName ?? stored;
    }
  }

  static Color _sourceColor(String stored) {
    switch (stored) {
      case SeriesSource.localService:
        return const Color(0xFF60A5FA);
      case SeriesSource.addonDirectService:
        return const Color(0xFFA78BFA);
      default:
        return switch (CloudProviderId.fromStoredId(stored)) {
          CloudProviderId.debrid => const Color(0xFF10B981),
          CloudProviderId.torbox => const Color(0xFF3B82F6),
          CloudProviderId.pikpak => const Color(0xFFF59E0B),
          CloudProviderId.premiumize => const Color(0xFFFB923C),
          CloudProviderId.alldebrid => const Color(0xFF26A69A),
          null => Colors.white54,
        };
    }
  }
}
