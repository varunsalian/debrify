import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Built-in font options for subtitles
class SubtitleFont {
  final String id;
  final String label;
  final String? fontFamily; // null means system default

  const SubtitleFont({
    required this.id,
    required this.label,
    this.fontFamily,
  });

  bool get isCustom => id == 'custom';
  bool get isDefault => id == 'default';

  /// 10 bundled fonts + custom option
  static const List<SubtitleFont> builtInOptions = [
    SubtitleFont(id: 'default', label: 'Default', fontFamily: null),
    SubtitleFont(id: 'roboto', label: 'Roboto', fontFamily: 'Roboto'),
    SubtitleFont(id: 'opensans', label: 'Open Sans', fontFamily: 'OpenSans'),
    SubtitleFont(id: 'inter', label: 'Inter', fontFamily: 'Inter'),
    SubtitleFont(id: 'lato', label: 'Lato', fontFamily: 'Lato'),
    SubtitleFont(id: 'poppins', label: 'Poppins', fontFamily: 'Poppins'),
    SubtitleFont(id: 'nunito', label: 'Nunito', fontFamily: 'Nunito'),
    SubtitleFont(id: 'merriweather', label: 'Merriweather', fontFamily: 'Merriweather'),
    SubtitleFont(id: 'sourceserif', label: 'Source Serif', fontFamily: 'SourceSerifPro'),
    SubtitleFont(id: 'firamono', label: 'Fira Mono', fontFamily: 'FiraMono'),
    SubtitleFont(id: 'notosans', label: 'Noto Sans', fontFamily: 'NotoSans'),
    SubtitleFont(id: 'custom', label: 'Custom Font', fontFamily: null),
  ];

  static const int defaultIndex = 0;
}

/// Service for managing custom subtitle fonts
class SubtitleFontService {
  static const String _keyFontIndex = 'subtitle_font_index';
  static const String _keyCustomFontPath = 'subtitle_custom_font_path';
  static const String _keyCustomFontName = 'subtitle_custom_font_name';
  static const String _customFontFamily = 'CustomSubtitleFont';
  static const String _customFontDir = 'subtitle_fonts';

  static SubtitleFontService? _instance;
  static SubtitleFontService get instance {
    _instance ??= SubtitleFontService._();
    return _instance!;
  }

  SubtitleFontService._();

  SharedPreferences? _prefs;
  bool _customFontLoaded = false;
  String? _loadedCustomFontPath;

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Get current font index
  Future<int> getFontIndex() async {
    await _ensurePrefs();
    return _prefs!.getInt(_keyFontIndex) ?? SubtitleFont.defaultIndex;
  }

  /// Set font index
  Future<void> setFontIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
        _keyFontIndex, index.clamp(0, SubtitleFont.builtInOptions.length - 1));
  }

  /// Get custom font path (if set)
  Future<String?> getCustomFontPath() async {
    await _ensurePrefs();
    return _prefs!.getString(_keyCustomFontPath);
  }

  /// Get custom font display name
  Future<String?> getCustomFontName() async {
    await _ensurePrefs();
    return _prefs!.getString(_keyCustomFontName);
  }

  /// Get current font option
  Future<SubtitleFont> getCurrentFont() async {
    final idx = await getFontIndex();
    return SubtitleFont
        .builtInOptions[idx.clamp(0, SubtitleFont.builtInOptions.length - 1)];
  }

  /// Get the font family to use for subtitles
  /// Returns null for system default, or the appropriate font family string
  Future<String?> getFontFamily() async {
    final font = await getCurrentFont();

    if (font.isCustom) {
      // Check if custom font is loaded
      if (await _ensureCustomFontLoaded()) {
        return _customFontFamily;
      }
      // Fallback to default if custom font not available
      return null;
    }

    return font.fontFamily;
  }

  /// Import a custom font file
  /// Returns true if successful, false otherwise
  Future<bool> importCustomFont(String sourcePath, String fileName) async {
    try {
      await _ensurePrefs();

      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final fontDir = Directory('${appDir.path}/$_customFontDir');

      // Create font directory if it doesn't exist
      if (!await fontDir.exists()) {
        await fontDir.create(recursive: true);
      }

      // Copy font file to app directory
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return false;
      }

      final destPath = '${fontDir.path}/$fileName';
      await sourceFile.copy(destPath);

      // Save font path and name
      await _prefs!.setString(_keyCustomFontPath, destPath);
      await _prefs!.setString(_keyCustomFontName, _extractFontName(fileName));

      // Load the font
      await _loadCustomFont(destPath);

      // Set font index to custom
      final customIndex = SubtitleFont.builtInOptions
          .indexWhere((f) => f.id == 'custom');
      if (customIndex >= 0) {
        await setFontIndex(customIndex);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Remove custom font
  Future<void> removeCustomFont() async {
    await _ensurePrefs();

    final fontPath = await getCustomFontPath();
    if (fontPath != null) {
      try {
        final file = File(fontPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    await _prefs!.remove(_keyCustomFontPath);
    await _prefs!.remove(_keyCustomFontName);
    _customFontLoaded = false;
    _loadedCustomFontPath = null;

    // Reset to default font
    await setFontIndex(SubtitleFont.defaultIndex);
  }

  /// Check if custom font is available
  Future<bool> hasCustomFont() async {
    final path = await getCustomFontPath();
    if (path == null) return false;

    final file = File(path);
    return await file.exists();
  }

  /// Ensure custom font is loaded into Flutter's font registry
  Future<bool> _ensureCustomFontLoaded() async {
    final fontPath = await getCustomFontPath();
    if (fontPath == null) return false;

    // Already loaded this font
    if (_customFontLoaded && _loadedCustomFontPath == fontPath) {
      return true;
    }

    return await _loadCustomFont(fontPath);
  }

  /// Load a custom font file into Flutter
  Future<bool> _loadCustomFont(String fontPath) async {
    try {
      final file = File(fontPath);
      if (!await file.exists()) return false;

      final fontData = await file.readAsBytes();
      final fontLoader = FontLoader(_customFontFamily);
      fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
      await fontLoader.load();

      _customFontLoaded = true;
      _loadedCustomFontPath = fontPath;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Extract display name from font filename
  String _extractFontName(String fileName) {
    // Remove extension
    var name = fileName;
    if (name.toLowerCase().endsWith('.ttf') ||
        name.toLowerCase().endsWith('.otf')) {
      name = name.substring(0, name.length - 4);
    }

    // Replace common separators with spaces
    name = name.replaceAll(RegExp(r'[-_]'), ' ');

    // Capitalize first letter of each word
    return name.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  /// Cycle to next font option
  Future<int> cycleFontUp() async {
    final current = await getFontIndex();
    final options = await _getAvailableOptions();
    final currentInOptions = options.indexWhere(
        (i) => i == current);
    final nextIndex = (currentInOptions + 1) % options.length;
    await setFontIndex(options[nextIndex]);
    return options[nextIndex];
  }

  /// Cycle to previous font option
  Future<int> cycleFontDown() async {
    final current = await getFontIndex();
    final options = await _getAvailableOptions();
    final currentInOptions = options.indexWhere(
        (i) => i == current);
    final prevIndex = currentInOptions == 0
        ? options.length - 1
        : currentInOptions - 1;
    await setFontIndex(options[prevIndex]);
    return options[prevIndex];
  }

  /// Get available font option indices (excludes custom if not set)
  Future<List<int>> _getAvailableOptions() async {
    final hasCustom = await hasCustomFont();
    final options = <int>[];

    for (var i = 0; i < SubtitleFont.builtInOptions.length; i++) {
      final font = SubtitleFont.builtInOptions[i];
      if (font.isCustom && !hasCustom) continue;
      options.add(i);
    }

    return options;
  }

  /// Get display label for current font
  Future<String> getCurrentFontLabel() async {
    final font = await getCurrentFont();
    if (font.isCustom) {
      final customName = await getCustomFontName();
      return customName ?? 'Custom Font';
    }
    return font.label;
  }

  /// Reset font to default
  Future<void> resetToDefault() async {
    await setFontIndex(SubtitleFont.defaultIndex);
  }

  /// Initialize - call on app startup to preload custom font if set
  Future<void> initialize() async {
    await _ensurePrefs();
    final font = await getCurrentFont();
    if (font.isCustom) {
      await _ensureCustomFontLoaded();
    }
  }
}
