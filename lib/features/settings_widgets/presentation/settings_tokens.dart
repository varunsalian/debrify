import 'package:flutter/material.dart';

/// Shared visual tokens for the Settings screens.
///
/// These mirror the Stremio board constants in `search_screen.dart`
/// (`kStremioBg` / `kStremioAccent`) and `see_all_theme.dart` so Settings
/// finally matches the Discover look. Duplicated on purpose — importing
/// `search_screen.dart` from here would be a layering smell.
const Color kSettingsBg = Color(0xFF0D0B1A);

const Color kSettingsAccent = Color(0xFF7B5CFF);

const Color kSettingsAccent2 = Color(0xFF9B7BFF);

const Color kSettingsPanel = Color(0xFF17132E);

const Color kSettingsPanel2 = Color(0xFF1E1840);

const Color kSettingsGreen = Color(0xFF39D98A);

const Color kSettingsRed = Color(0xFFE5484D);

const Color kSettingsAmber = Color(0xFFF5A623);

/// Thin hairline used for panel borders and row dividers.
final Color kSettingsLine = const Color(0xFFB4A0FF).withValues(alpha: 0.12);

final Color kSettingsDim = Colors.white.withValues(alpha: 0.46);

final Color kSettingsDim2 = Colors.white.withValues(alpha: 0.28);

/// Max content width for the settings column so it doesn't stretch
/// edge-to-edge on TV/desktop.
const double kSettingsMaxWidth = 720;
