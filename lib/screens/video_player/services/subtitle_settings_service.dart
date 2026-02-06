import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/subtitle_font_service.dart';

/// Subtitle size options
class SubtitleSize {
  final String label;
  final double sizePx;

  const SubtitleSize(this.label, this.sizePx);

  static const List<SubtitleSize> options = [
    SubtitleSize('Tiny', 28),
    SubtitleSize('Small', 34),
    SubtitleSize('Medium', 42),
    SubtitleSize('Large', 52),
    SubtitleSize('X-Large', 64),
    SubtitleSize('Huge', 76),
    SubtitleSize('Giant', 90),
  ];

  static const int defaultIndex = 2; // Medium
}

/// Subtitle edge style options
class SubtitleStyle {
  final String label;
  final List<Shadow>? shadows;
  final Paint? foregroundPaint;

  const SubtitleStyle(this.label, {this.shadows, this.foregroundPaint});

  static List<SubtitleStyle> get options => [
        const SubtitleStyle('None'),
        SubtitleStyle('Outline', shadows: _outlineShadows),
        SubtitleStyle('Shadow', shadows: _dropShadow),
        SubtitleStyle('Raised', shadows: _raisedShadows),
        SubtitleStyle('Depressed', shadows: _depressedShadows),
      ];

  static const int defaultIndex = 1; // Outline

  static List<Shadow> get _outlineShadows => [
        const Shadow(offset: Offset(-1.5, -1.5), color: Colors.black),
        const Shadow(offset: Offset(1.5, -1.5), color: Colors.black),
        const Shadow(offset: Offset(-1.5, 1.5), color: Colors.black),
        const Shadow(offset: Offset(1.5, 1.5), color: Colors.black),
      ];

  static List<Shadow> get _dropShadow => [
        const Shadow(offset: Offset(2, 2), blurRadius: 4, color: Colors.black87),
      ];

  static List<Shadow> get _raisedShadows => [
        const Shadow(offset: Offset(-1, -1), color: Colors.white24),
        const Shadow(offset: Offset(2, 2), blurRadius: 2, color: Colors.black),
      ];

  static List<Shadow> get _depressedShadows => [
        const Shadow(offset: Offset(1, 1), color: Colors.white24),
        const Shadow(offset: Offset(-1, -1), blurRadius: 2, color: Colors.black),
      ];
}

/// Subtitle text color options
class SubtitleColor {
  final String label;
  final Color color;

  const SubtitleColor(this.label, this.color);

  static const List<SubtitleColor> options = [
    SubtitleColor('White', Colors.white),
    SubtitleColor('Yellow', Color(0xFFFFFF00)),
    SubtitleColor('Cyan', Color(0xFF00FFFF)),
    SubtitleColor('Green', Color(0xFF00FF00)),
    SubtitleColor('Magenta', Color(0xFFFF00FF)),
    SubtitleColor('Red', Color(0xFFFF4444)),
    SubtitleColor('Blue', Color(0xFF4488FF)),
    SubtitleColor('Orange', Color(0xFFFF8800)),
  ];

  static const int defaultIndex = 0; // White
}

/// Subtitle background options
class SubtitleBackground {
  final String label;
  final Color color;

  const SubtitleBackground(this.label, this.color);

  static const List<SubtitleBackground> options = [
    SubtitleBackground('None', Colors.transparent),
    SubtitleBackground('Light', Color(0x40000000)),
    SubtitleBackground('Medium', Color(0x80000000)),
    SubtitleBackground('Dark', Color(0xB3000000)),
    SubtitleBackground('Solid', Color(0xE6000000)),
  ];

  static const int defaultIndex = 0; // None
}

/// Service for managing subtitle appearance settings with persistence.
class SubtitleSettingsService {
  // Keys match Android's SubtitleSettings for cross-platform consistency
  static const String _keySizeIndex = 'subtitle_size_index';
  static const String _keyStyleIndex = 'subtitle_style_index';
  static const String _keyColorIndex = 'subtitle_color_index';
  static const String _keyBgIndex = 'subtitle_bg_index';

  static SubtitleSettingsService? _instance;
  static SubtitleSettingsService get instance {
    _instance ??= SubtitleSettingsService._();
    return _instance!;
  }

  SubtitleSettingsService._();

  SharedPreferences? _prefs;

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // Getters
  Future<int> getSizeIndex() async {
    await _ensurePrefs();
    return _prefs!.getInt(_keySizeIndex) ?? SubtitleSize.defaultIndex;
  }

  Future<int> getStyleIndex() async {
    await _ensurePrefs();
    return _prefs!.getInt(_keyStyleIndex) ?? SubtitleStyle.defaultIndex;
  }

  Future<int> getColorIndex() async {
    await _ensurePrefs();
    return _prefs!.getInt(_keyColorIndex) ?? SubtitleColor.defaultIndex;
  }

  Future<int> getBgIndex() async {
    await _ensurePrefs();
    return _prefs!.getInt(_keyBgIndex) ?? SubtitleBackground.defaultIndex;
  }

  // Setters
  Future<void> setSizeIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
        _keySizeIndex, index.clamp(0, SubtitleSize.options.length - 1));
  }

  Future<void> setStyleIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
        _keyStyleIndex, index.clamp(0, SubtitleStyle.options.length - 1));
  }

  Future<void> setColorIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
        _keyColorIndex, index.clamp(0, SubtitleColor.options.length - 1));
  }

  Future<void> setBgIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
        _keyBgIndex, index.clamp(0, SubtitleBackground.options.length - 1));
  }

  // Get current values
  Future<SubtitleSize> getCurrentSize() async {
    final idx = await getSizeIndex();
    return SubtitleSize.options[idx.clamp(0, SubtitleSize.options.length - 1)];
  }

  Future<SubtitleStyle> getCurrentStyle() async {
    final idx = await getStyleIndex();
    return SubtitleStyle.options[idx.clamp(0, SubtitleStyle.options.length - 1)];
  }

  Future<SubtitleColor> getCurrentColor() async {
    final idx = await getColorIndex();
    return SubtitleColor.options[idx.clamp(0, SubtitleColor.options.length - 1)];
  }

  Future<SubtitleBackground> getCurrentBg() async {
    final idx = await getBgIndex();
    return SubtitleBackground
        .options[idx.clamp(0, SubtitleBackground.options.length - 1)];
  }

  /// Load all settings at once
  Future<SubtitleSettingsData> loadAll() async {
    await _ensurePrefs();
    final fontService = SubtitleFontService.instance;
    final fontIndex = await fontService.getFontIndex();
    final fontFamily = await fontService.getFontFamily();
    final selectedFont = await fontService.getSelectedFont();

    return SubtitleSettingsData(
      sizeIndex: _prefs!.getInt(_keySizeIndex) ?? SubtitleSize.defaultIndex,
      styleIndex: _prefs!.getInt(_keyStyleIndex) ?? SubtitleStyle.defaultIndex,
      colorIndex: _prefs!.getInt(_keyColorIndex) ?? SubtitleColor.defaultIndex,
      bgIndex: _prefs!.getInt(_keyBgIndex) ?? SubtitleBackground.defaultIndex,
      fontIndex: fontIndex,
      fontFamily: fontFamily,
      fontLabel: selectedFont.label,
    );
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    await _ensurePrefs();
    await _prefs!.setInt(_keySizeIndex, SubtitleSize.defaultIndex);
    await _prefs!.setInt(_keyStyleIndex, SubtitleStyle.defaultIndex);
    await _prefs!.setInt(_keyColorIndex, SubtitleColor.defaultIndex);
    await _prefs!.setInt(_keyBgIndex, SubtitleBackground.defaultIndex);
    await SubtitleFontService.instance.resetToDefault();
  }

  /// Check if settings are at defaults
  Future<bool> isDefault() async {
    final data = await loadAll();
    return data.sizeIndex == SubtitleSize.defaultIndex &&
        data.styleIndex == SubtitleStyle.defaultIndex &&
        data.colorIndex == SubtitleColor.defaultIndex &&
        data.bgIndex == SubtitleBackground.defaultIndex &&
        data.fontIndex == SubtitleFont.defaultIndex;
  }
}

/// Holds all subtitle settings data
class SubtitleSettingsData {
  final int sizeIndex;
  final int styleIndex;
  final int colorIndex;
  final int bgIndex;
  final int fontIndex;
  final String? fontFamily; // Resolved font family (null = system default)
  final String fontLabel; // Display label for the font

  const SubtitleSettingsData({
    required this.sizeIndex,
    required this.styleIndex,
    required this.colorIndex,
    required this.bgIndex,
    this.fontIndex = 0,
    this.fontFamily,
    this.fontLabel = 'Default',
  });

  SubtitleSize get size =>
      SubtitleSize.options[sizeIndex.clamp(0, SubtitleSize.options.length - 1)];

  SubtitleStyle get style => SubtitleStyle
      .options[styleIndex.clamp(0, SubtitleStyle.options.length - 1)];

  SubtitleColor get color => SubtitleColor
      .options[colorIndex.clamp(0, SubtitleColor.options.length - 1)];

  SubtitleBackground get background => SubtitleBackground
      .options[bgIndex.clamp(0, SubtitleBackground.options.length - 1)];

  SubtitleFont get font => SubtitleFont(
      id: fontIndex.toString(),
      label: fontLabel,
      fontFamily: fontFamily,
    );

  /// Build TextStyle for subtitles
  TextStyle buildTextStyle() {
    return TextStyle(
      fontSize: size.sizePx,
      color: color.color,
      fontWeight: FontWeight.w600,
      shadows: style.shadows,
      backgroundColor: background.color,
      fontFamily: fontFamily,
    );
  }

  SubtitleSettingsData copyWith({
    int? sizeIndex,
    int? styleIndex,
    int? colorIndex,
    int? bgIndex,
    int? fontIndex,
    String? fontFamily,
    String? fontLabel,
  }) {
    return SubtitleSettingsData(
      sizeIndex: sizeIndex ?? this.sizeIndex,
      styleIndex: styleIndex ?? this.styleIndex,
      colorIndex: colorIndex ?? this.colorIndex,
      bgIndex: bgIndex ?? this.bgIndex,
      fontIndex: fontIndex ?? this.fontIndex,
      fontFamily: fontFamily ?? this.fontFamily,
      fontLabel: fontLabel ?? this.fontLabel,
    );
  }
}
