import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a subtitle font option (built-in or custom)
class SubtitleFont {
  final String id;
  final String label;
  final String? fontFamily; // null means system default
  final bool isCustom;
  final String? path; // Only for custom fonts

  const SubtitleFont({
    required this.id,
    required this.label,
    this.fontFamily,
    this.isCustom = false,
    this.path,
  });

  bool get isDefault => id == 'default';

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'fontFamily': fontFamily,
    'path': path,
  };

  factory SubtitleFont.fromJson(Map<String, dynamic> json) => SubtitleFont(
    id: json['id'] as String,
    label: json['label'] as String,
    fontFamily: json['fontFamily'] as String?,
    isCustom: true,
    path: json['path'] as String?,
  );

  /// Built-in font options
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
  ];

  static const int defaultIndex = 0;
}

/// Service for managing subtitle fonts (built-in + unlimited custom fonts)
class SubtitleFontService {
  static const String _keySelectedFontId = 'subtitle_selected_font_id';
  static const String _keyCustomFonts = 'subtitle_custom_fonts';
  static const String _customFontDir = 'subtitle_fonts';

  static SubtitleFontService? _instance;
  static SubtitleFontService get instance {
    _instance ??= SubtitleFontService._();
    return _instance!;
  }

  SubtitleFontService._();

  SharedPreferences? _prefs;
  final Set<String> _loadedFontFamilies = {};
  List<SubtitleFont>? _cachedCustomFonts;

  Future<void> _ensurePrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Get all available fonts (built-in + custom)
  Future<List<SubtitleFont>> getAllFonts() async {
    final customFonts = await getCustomFonts();
    return [...SubtitleFont.builtInOptions, ...customFonts];
  }

  /// Get custom fonts list
  Future<List<SubtitleFont>> getCustomFonts() async {
    if (_cachedCustomFonts != null) return _cachedCustomFonts!;

    await _ensurePrefs();
    final jsonStr = _prefs!.getString(_keyCustomFonts);
    if (jsonStr == null || jsonStr.isEmpty) {
      _cachedCustomFonts = [];
      return [];
    }

    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      _cachedCustomFonts = jsonList
          .map((json) => SubtitleFont.fromJson(json as Map<String, dynamic>))
          .toList();
      return _cachedCustomFonts!;
    } catch (e) {
      _cachedCustomFonts = [];
      return [];
    }
  }

  /// Save custom fonts list
  Future<void> _saveCustomFonts(List<SubtitleFont> fonts) async {
    await _ensurePrefs();
    final jsonList = fonts.map((f) => f.toJson()).toList();
    await _prefs!.setString(_keyCustomFonts, jsonEncode(jsonList));
    _cachedCustomFonts = fonts;
  }

  /// Get selected font ID
  Future<String> getSelectedFontId() async {
    await _ensurePrefs();
    return _prefs!.getString(_keySelectedFontId) ?? 'default';
  }

  /// Set selected font ID
  Future<void> setSelectedFontId(String fontId) async {
    await _ensurePrefs();
    await _prefs!.setString(_keySelectedFontId, fontId);
  }

  /// Get selected font index in the combined list
  Future<int> getSelectedFontIndex() async {
    final allFonts = await getAllFonts();
    final selectedId = await getSelectedFontId();
    final index = allFonts.indexWhere((f) => f.id == selectedId);
    return index >= 0 ? index : 0;
  }

  /// Set selected font by index in the combined list
  Future<void> setSelectedFontByIndex(int index) async {
    final allFonts = await getAllFonts();
    if (index >= 0 && index < allFonts.length) {
      await setSelectedFontId(allFonts[index].id);
    }
  }

  /// Get current selected font
  Future<SubtitleFont> getSelectedFont() async {
    final allFonts = await getAllFonts();
    final selectedId = await getSelectedFontId();
    return allFonts.firstWhere(
      (f) => f.id == selectedId,
      orElse: () => SubtitleFont.builtInOptions.first,
    );
  }

  /// Get the font family string for the selected font
  /// Returns null for system default
  Future<String?> getFontFamily() async {
    final font = await getSelectedFont();

    if (font.isCustom && font.path != null) {
      // Ensure custom font is loaded
      await _ensureCustomFontLoaded(font);
      return font.fontFamily;
    }

    return font.fontFamily;
  }

  /// Import a custom font file
  /// Returns the new font if successful, null otherwise
  Future<SubtitleFont?> importCustomFont(String sourcePath, String fileName) async {
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
        return null;
      }

      // Generate unique ID and font family name
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fontId = 'custom_$timestamp';
      final fontFamily = 'CustomFont_$timestamp';

      final destPath = '${fontDir.path}/${fontId}_$fileName';
      await sourceFile.copy(destPath);

      // Create font entry
      final fontName = _extractFontName(fileName);
      final newFont = SubtitleFont(
        id: fontId,
        label: fontName,
        fontFamily: fontFamily,
        isCustom: true,
        path: destPath,
      );

      // Load the font into Flutter
      final loaded = await _loadCustomFont(newFont);
      if (!loaded) {
        // Clean up if loading failed
        try {
          await File(destPath).delete();
        } catch (_) {}
        return null;
      }

      // Add to custom fonts list
      final customFonts = await getCustomFonts();
      customFonts.add(newFont);
      await _saveCustomFonts(customFonts);

      // Select the new font
      await setSelectedFontId(fontId);

      return newFont;
    } catch (e) {
      return null;
    }
  }

  /// Remove a custom font by ID
  Future<void> removeCustomFont(String fontId) async {
    final customFonts = await getCustomFonts();
    final fontIndex = customFonts.indexWhere((f) => f.id == fontId);

    if (fontIndex < 0) return;

    final font = customFonts[fontIndex];

    // Delete the font file
    if (font.path != null) {
      try {
        final file = File(font.path!);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    // Remove from list
    customFonts.removeAt(fontIndex);
    await _saveCustomFonts(customFonts);

    // If this was the selected font, reset to default
    final selectedId = await getSelectedFontId();
    if (selectedId == fontId) {
      await setSelectedFontId('default');
    }
  }

  /// Check if any custom fonts are available
  Future<bool> hasCustomFonts() async {
    final fonts = await getCustomFonts();
    return fonts.isNotEmpty;
  }

  /// Ensure a custom font is loaded into Flutter's font registry
  Future<bool> _ensureCustomFontLoaded(SubtitleFont font) async {
    if (!font.isCustom || font.path == null || font.fontFamily == null) {
      return false;
    }

    // Already loaded
    if (_loadedFontFamilies.contains(font.fontFamily)) {
      return true;
    }

    return await _loadCustomFont(font);
  }

  /// Load a custom font file into Flutter
  Future<bool> _loadCustomFont(SubtitleFont font) async {
    if (font.path == null || font.fontFamily == null) return false;

    try {
      final file = File(font.path!);
      if (!await file.exists()) return false;

      final fontData = await file.readAsBytes();
      final fontLoader = FontLoader(font.fontFamily!);
      fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
      await fontLoader.load();

      _loadedFontFamilies.add(font.fontFamily!);
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

  /// Initialize - call on app startup to preload selected custom font
  Future<void> initialize() async {
    await _ensurePrefs();
    final font = await getSelectedFont();
    if (font.isCustom) {
      await _ensureCustomFontLoaded(font);
    }
  }

  /// Reset to default font
  Future<void> resetToDefault() async {
    await setSelectedFontId('default');
  }

  // Legacy compatibility methods for settings service
  Future<int> getFontIndex() => getSelectedFontIndex();

  Future<void> setFontIndex(int index) => setSelectedFontByIndex(index);

  /// Cycle to previous font (wraps around)
  Future<int> cycleFontDown() async {
    final allFonts = await getAllFonts();
    final currentIndex = await getSelectedFontIndex();
    final newIndex = currentIndex <= 0 ? allFonts.length - 1 : currentIndex - 1;
    await setSelectedFontByIndex(newIndex);
    return newIndex;
  }

  /// Cycle to next font (wraps around)
  Future<int> cycleFontUp() async {
    final allFonts = await getAllFonts();
    final currentIndex = await getSelectedFontIndex();
    final newIndex = currentIndex >= allFonts.length - 1 ? 0 : currentIndex + 1;
    await setSelectedFontByIndex(newIndex);
    return newIndex;
  }
}
