import 'dart:ui' show Color;

import '../series_source_service.dart';
import 'cloud_provider_id.dart';

/// Provider labels, chip codes and gradients as pure data (dart:ui only),
/// so services can name a provider without reaching into lib/widgets.
/// String identity lives on [CloudProviderId]; `CloudProviderChrome`
/// (lib/widgets) adds the Material icon and the bind-source chip on top.
///
/// Lookup rules, on purpose:
/// - [label]/[code]/[gradient]: exact playback id (`debrid`, not `rd`)
/// - [catalogChip]/[catalogTitle]: [CloudProviderId.tryParse]; `auto` -> AUTO
/// - [playlistBadge]: playlist JSON; empty -> RD, `webdav` -> DV, else two letters
class CloudProviderPresentation {
  CloudProviderPresentation._();

  static const _indigo = [Color(0xFF6366F1), Color(0xFF4338CA)];

  static String label(String provider) {
    switch (provider) {
      case 'preparing':
        return 'Preparing';
      case SeriesSource.localService:
        return 'On-device';
      case SeriesSource.addonDirectService:
        return 'Direct addon';
      case 'stream':
        return 'Stream';
      default:
        return CloudProviderId.fromPlaybackId(provider)?.displayName ??
            provider;
    }
  }

  static String code(String provider) {
    switch (provider) {
      case 'preparing':
        return '···';
      case 'stream':
        return 'TV';
      case SeriesSource.addonDirectService:
        return 'DL';
      default:
        final cloud = CloudProviderId.fromPlaybackId(provider);
        if (cloud != null) return cloud.chipCode;
        return provider.isEmpty ? '·' : provider.substring(0, 1).toUpperCase();
    }
  }

  static List<Color> gradient(String provider) {
    return switch (CloudProviderId.fromPlaybackId(provider)) {
      CloudProviderId.debrid => const [
        Color(0xFF10B981),
        Color(0xFF059669),
      ],
      CloudProviderId.torbox => const [
        Color(0xFF8B5CF6),
        Color(0xFF7C3AED),
      ],
      CloudProviderId.premiumize => const [
        Color(0xFFF59E0B),
        Color(0xFFD97706),
      ],
      CloudProviderId.alldebrid => const [
        Color(0xFF26A69A),
        Color(0xFF00796B),
      ],
      CloudProviderId.pikpak || null => _indigo,
    };
  }

  /// `auto` / unknown -> `AUTO`, not the first letter of the string.
  static String catalogChip(String provider) {
    final id = CloudProviderId.tryParse(provider);
    if (id == null) return 'AUTO';
    return id.chipCode;
  }

  static String? catalogTitle(String provider) {
    return CloudProviderId.tryParse(provider)?.displayName;
  }

  /// Playlist card glyph. Not [catalogChip]: empty is RD, unknown is two
  /// letters, WebDAV is DV.
  static String playlistBadge(String? raw) {
    if (raw == null || raw.isEmpty) return CloudProviderId.debrid.chipCode;
    switch (raw.toLowerCase()) {
      case 'webdav':
        return 'DV';
      case 'pik-pak':
      case 'pik_pak':
        return CloudProviderId.pikpak.chipCode;
      default:
        return CloudProviderId.tryParse(raw)?.chipCode ??
            raw.substring(0, 2).toUpperCase();
    }
  }
}
