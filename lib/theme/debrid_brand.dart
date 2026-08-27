import 'package:flutter/material.dart';

import '../features/debrid/descriptor.dart';

/// A provider's brand ink. Two palettes, both pre-existing and deliberately
/// different: [tile] is the flat chip colour on source lists, [accent] and
/// [accentDeep] are the play-loader gradient.
///
/// NOT YET ADOPTED: `torrent_playback_service.dart` still carries the same
/// values in its own `_providerGradient`/`_providerIcon` switches.
class DebridBrand {
  final Color tile;
  final Color accent;
  final Color accentDeep;
  final IconData icon;

  const DebridBrand({
    required this.tile,
    required this.accent,
    required this.accentDeep,
    required this.icon,
  });

  List<Color> get gradient => [accent, accentDeep];
}

const _brands = <String, DebridBrand>{
  DebridProviderIds.realDebrid: DebridBrand(
    tile: Color(0xFF10B981),
    accent: Color(0xFF10B981),
    accentDeep: Color(0xFF059669),
    icon: Icons.cloud_download_rounded,
  ),
  DebridProviderIds.torbox: DebridBrand(
    tile: Color(0xFF3B82F6),
    accent: Color(0xFF8B5CF6),
    accentDeep: Color(0xFF7C3AED),
    icon: Icons.flash_on_rounded,
  ),
  DebridProviderIds.premiumize: DebridBrand(
    tile: Color(0xFFFB923C),
    accent: Color(0xFFF59E0B),
    accentDeep: Color(0xFFD97706),
    icon: Icons.workspace_premium_rounded,
  ),
  DebridProviderIds.allDebrid: DebridBrand(
    tile: Color(0xFF26A69A),
    accent: Color(0xFF26A69A),
    accentDeep: Color(0xFF00796B),
    icon: Icons.all_inclusive_rounded,
  ),
  DebridProviderIds.pikpak: DebridBrand(
    tile: Color(0xFFF59E0B),
    accent: Color(0xFF6366F1),
    accentDeep: Color(0xFF4338CA),
    icon: Icons.cloud_circle_rounded,
  ),
};

/// The fallback the old switches fell through to: PikPak's indigo gradient and
/// Real-Debrid's cloud glyph.
const debridBrandFallback = DebridBrand(
  tile: Colors.white54,
  accent: Color(0xFF6366F1),
  accentDeep: Color(0xFF4338CA),
  icon: Icons.cloud_download_rounded,
);

/// Brand for any spelling of a provider id, or [debridBrandFallback] for `none`,
/// `auto`, a local binding, or an addon stream.
DebridBrand debridBrandFor(String? providerId) {
  final id = DebridProviderIds.normalize(providerId);
  return id == null ? debridBrandFallback : _brands[id]!;
}
