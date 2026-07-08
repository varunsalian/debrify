import 'package:flutter/material.dart';

/// Shared visual tokens for the "See All" browse/grid screens.
///
/// These mirror the Stremio board constants in `search_screen.dart`
/// (`kStremioBg` / `kStremioAccent` etc.) but are duplicated here on purpose:
/// the See-All widgets are imported *by* `search_screen`, so importing back into
/// it for the constants would create a dependency cycle. Keep these in sync with
/// the board tokens.
const Color kSeeAllBg = Color(0xFF0D0B1A);
const Color kSeeAllAccent = Color(0xFF7B5CFF);
const Color kSeeAllAccent2 = Color(0xFF9B7BFF);
const Color kSeeAllPanel = Color(0xFF17132E);
const Color kSeeAllPanel2 = Color(0xFF1E1840);

/// Accent border used by pills / dropdowns on hover.
final Color kSeeAllAccentBorder = kSeeAllAccent.withValues(alpha: 0.38);
final Color kSeeAllLine = const Color(0xFFB4A0FF).withValues(alpha: 0.12);
