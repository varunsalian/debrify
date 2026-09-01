import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/subtitle_font_service.dart';
import '../../../services/profiles/profile_preferences.dart';

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

  // An 8-point ring on one circle, not the old 4 diagonal copies: diagonals
  // alone leave the cardinal directions uncovered, so glyph tops, bottoms and
  // sides showed notches that read as a broken, blurry outline (Discord
  // report, "no matter the font").
  static const double _outlineRadius = 1.5;
  // _outlineRadius / sqrt2, so the diagonal copies sit on the same circle.
  static const double _outlineDiagonal = 1.06;

  static List<Shadow> get _outlineShadows => const [
    Shadow(offset: Offset(-_outlineRadius, 0), color: Colors.black),
    Shadow(offset: Offset(_outlineRadius, 0), color: Colors.black),
    Shadow(offset: Offset(0, -_outlineRadius), color: Colors.black),
    Shadow(offset: Offset(0, _outlineRadius), color: Colors.black),
    Shadow(
      offset: Offset(-_outlineDiagonal, -_outlineDiagonal),
      color: Colors.black,
    ),
    Shadow(
      offset: Offset(_outlineDiagonal, -_outlineDiagonal),
      color: Colors.black,
    ),
    Shadow(
      offset: Offset(-_outlineDiagonal, _outlineDiagonal),
      color: Colors.black,
    ),
    Shadow(
      offset: Offset(_outlineDiagonal, _outlineDiagonal),
      color: Colors.black,
    ),
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

/// Subtitle outline/edge color options
class SubtitleOutlineColor {
  final String label;
  final Color? color; // null = auto (contrast-based)

  const SubtitleOutlineColor(this.label, this.color);

  static const List<SubtitleOutlineColor> options = [
    SubtitleOutlineColor('Auto', null),
    SubtitleOutlineColor('Black', Colors.black),
    SubtitleOutlineColor('White', Colors.white),
    SubtitleOutlineColor('Yellow', Color(0xFFFFFF00)),
    SubtitleOutlineColor('Cyan', Color(0xFF00FFFF)),
    SubtitleOutlineColor('Green', Color(0xFF00FF00)),
    SubtitleOutlineColor('Magenta', Color(0xFFFF00FF)),
    SubtitleOutlineColor('Red', Color(0xFFFF4444)),
    SubtitleOutlineColor('Blue', Color(0xFF4488FF)),
    SubtitleOutlineColor('Orange', Color(0xFFFF8800)),
  ];

  static const int defaultIndex = 0; // Auto
}

/// Subtitle elevation (vertical position) options
class SubtitleElevation {
  final String label;
  final double bottomPadding; // bottom padding in pixels

  const SubtitleElevation(this.label, this.bottomPadding);

  static const List<SubtitleElevation> options = [
    SubtitleElevation('Bottom', 48),
    SubtitleElevation('Low', 80),
    SubtitleElevation('Medium', 120),
    SubtitleElevation('High', 180),
    SubtitleElevation('Higher', 260),
    // Appended so existing persisted elevation indexes keep their meaning.
    SubtitleElevation('Extreme Bottom', 8),
  ];

  static const int defaultIndex = 5; // Extreme Bottom
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
  static const String _keyOutlineColorIndex = 'subtitle_outline_color_index';
  static const String _keyElevationIndex = 'subtitle_elevation_index';
  static const String _keyExtremeBottomDefaultAdopted =
      'subtitle_extreme_bottom_default_adopted_v1';
  static const String _keyBold = 'subtitle_bold';

  /// Default: bold off (normal weight). Matches Android's DEFAULT_BOLD.
  static const bool defaultBold = false;

  static const int syncOffsetMinMs = -3600000;
  static const int syncOffsetMaxMs = 3600000;
  static const int syncOffsetStepMs = 100;

  /// Per-profile memory of dialed-in syncs, keyed by content + subtitle
  /// identity: a most-recent-last JSON list of `[identity, offsetMs, scale]`.
  /// Same shape and cap as Android TV's `sync_offset_memory_v1`.
  static const String _keySyncMemory = 'subtitle_sync_offset_memory_v1';
  static const int _syncMemoryMax = 200;

  static SubtitleSettingsService? _instance;
  static SubtitleSettingsService get instance {
    _instance ??= SubtitleSettingsService._();
    return _instance!;
  }

  SubtitleSettingsService._();

  SharedPreferences? _prefs;

  // The sync offset is per-subtitle and lives only for the current playback
  // session — a delay calibrated for one subtitle file is meaningless for a
  // different subtitle or a different episode, so the LIVE value is in-memory
  // and reset whenever the subtitle or content changes. What persists is the
  // per-identity memory below: an explicit, announced recall at subtitle load
  // (never an ambient read) restores a sync the same content+subtitle had.
  // (The style settings above stay persisted; only the offset is session-scoped.)
  int _syncOffsetMs = 0;

  /// Framerate correction applied with the offset: display time = file time
  /// × scale + offset. 1.0 for every subtitle that merely needs a shift.
  double _syncScale = 1.0;

  /// The player's "what subtitle is on screen" key, set by the screen at
  /// subtitle load. Memory writes go under it; null means nothing is
  /// remembered (a slider dialed with subtitles off has no owner).
  String? _activeSubtitleIdentity;

  Future<void> _ensurePrefs() async {
    _prefs ??= await ProfilePreferences.instance();
    await _adoptExtremeBottomDefault(_prefs!);
  }

  Future<void> _adoptExtremeBottomDefault(SharedPreferences prefs) async {
    if (prefs.getBool(_keyExtremeBottomDefaultAdopted) ?? false) return;

    // Before Extreme Bottom existed, index 0 was also the default. Profiles
    // that persisted that old default would otherwise stay at 48 px forever,
    // even though the app now defaults MediaKit subtitles to 8 px. Migrate it
    // once, then mark the profile so a later explicit Bottom selection sticks.
    if (prefs.getInt(_keyElevationIndex) == 0) {
      final migrated = await prefs.setInt(
        _keyElevationIndex,
        SubtitleElevation.defaultIndex,
      );
      if (!migrated) return;
    }
    await prefs.setBool(_keyExtremeBottomDefaultAdopted, true);
  }

  void resetProfileScope() {
    _prefs = null;
    _syncOffsetMs = 0;
    _syncScale = 1.0;
    _activeSubtitleIdentity = null;
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

  Future<int> getOutlineColorIndex() async {
    await _ensurePrefs();
    return _prefs!.getInt(_keyOutlineColorIndex) ??
        SubtitleOutlineColor.defaultIndex;
  }

  Future<int> getElevationIndex() async {
    await _ensurePrefs();
    return _prefs!.getInt(_keyElevationIndex) ?? SubtitleElevation.defaultIndex;
  }

  Future<bool> getBold() async {
    await _ensurePrefs();
    return _prefs!.getBool(_keyBold) ?? defaultBold;
  }

  // Setters
  Future<void> setSizeIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
      _keySizeIndex,
      index.clamp(0, SubtitleSize.options.length - 1),
    );
  }

  Future<void> setStyleIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
      _keyStyleIndex,
      index.clamp(0, SubtitleStyle.options.length - 1),
    );
  }

  Future<void> setColorIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
      _keyColorIndex,
      index.clamp(0, SubtitleColor.options.length - 1),
    );
  }

  Future<void> setBgIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
      _keyBgIndex,
      index.clamp(0, SubtitleBackground.options.length - 1),
    );
  }

  Future<void> setOutlineColorIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
      _keyOutlineColorIndex,
      index.clamp(0, SubtitleOutlineColor.options.length - 1),
    );
  }

  Future<void> setElevationIndex(int index) async {
    await _ensurePrefs();
    await _prefs!.setInt(
      _keyElevationIndex,
      index.clamp(0, SubtitleElevation.options.length - 1),
    );
  }

  Future<void> setBold(bool value) async {
    await _ensurePrefs();
    await _prefs!.setBool(_keyBold, value);
  }

  Future<int> getSyncOffsetMs() async {
    return _syncOffsetMs;
  }

  double get syncScale => _syncScale;

  /// Persist per subtitle identity INSIDE the one setter every writer uses
  /// (stepper, line picker, auto-sync, verify) — whoever dials a sync in,
  /// the same content+subtitle restores it next session. A zero offset with
  /// no scale is "nothing to remember" and forgets the entry.
  Future<void> setSyncOffsetMs(int ms) async {
    _syncOffsetMs = ms.clamp(syncOffsetMinMs, syncOffsetMaxMs);
    await _rememberActiveSync();
  }

  Future<void> setSyncScale(double scale) async {
    _syncScale = scale.isFinite && scale > 0 ? scale : 1.0;
    await _rememberActiveSync();
  }

  /// Clear the live sync. Call when the subtitle or content changes. Never
  /// touches memory: a transition is not the user saying "zero".
  void resetSyncOffset() {
    _syncOffsetMs = 0;
    _syncScale = 1.0;
  }

  /// Register (or clear) the identity memory writes belong to. Does not
  /// change the live values — the screen resets those on its own seams.
  void setActiveSubtitleIdentity(String? identity) {
    _activeSubtitleIdentity = identity;
  }

  String? get activeSubtitleIdentity => _activeSubtitleIdentity;

  /// The remembered sync for [identity], or null. Pure read.
  Future<SubtitleSyncMemoryEntry?> recallSync(String identity) async {
    final entries = await _readSyncMemory();
    for (final entry in entries.reversed) {
      if (entry.identity != identity) continue;
      if (entry.offsetMs == 0 && entry.scale == 1.0) return null;
      return entry;
    }
    return null;
  }

  Future<void> _rememberActiveSync() async {
    final identity = _activeSubtitleIdentity;
    if (identity == null) return;
    final entries = await _readSyncMemory();
    entries.removeWhere((entry) => entry.identity == identity);
    if (_syncOffsetMs != 0 || _syncScale != 1.0) {
      entries.add(
        SubtitleSyncMemoryEntry(
          identity: identity,
          offsetMs: _syncOffsetMs,
          scale: _syncScale,
        ),
      );
    }
    final trimmed = entries.length <= _syncMemoryMax
        ? entries
        : entries.sublist(entries.length - _syncMemoryMax);
    await _ensurePrefs();
    await _prefs!.setString(
      _keySyncMemory,
      jsonEncode(<Object>[
        for (final entry in trimmed)
          <Object>[entry.identity, entry.offsetMs, entry.scale],
      ]),
    );
  }

  Future<List<SubtitleSyncMemoryEntry>> _readSyncMemory() async {
    await _ensurePrefs();
    final raw = _prefs!.getString(_keySyncMemory);
    if (raw == null || raw.isEmpty) return <SubtitleSyncMemoryEntry>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <SubtitleSyncMemoryEntry>[];
      final out = <SubtitleSyncMemoryEntry>[];
      for (final item in decoded) {
        if (item is! List || item.length < 2) continue;
        final identity = item[0];
        final offset = item[1];
        if (identity is! String || offset is! num) continue;
        final scale = item.length > 2 && item[2] is num
            ? (item[2] as num).toDouble()
            : 1.0;
        out.add(
          SubtitleSyncMemoryEntry(
            identity: identity,
            offsetMs: offset.toInt().clamp(syncOffsetMinMs, syncOffsetMaxMs),
            scale: scale.isFinite && scale > 0 ? scale : 1.0,
          ),
        );
      }
      return out;
    } catch (_) {
      return <SubtitleSyncMemoryEntry>[];
    }
  }

  // Get current values
  Future<SubtitleSize> getCurrentSize() async {
    final idx = await getSizeIndex();
    return SubtitleSize.options[idx.clamp(0, SubtitleSize.options.length - 1)];
  }

  Future<SubtitleStyle> getCurrentStyle() async {
    final idx = await getStyleIndex();
    return SubtitleStyle.options[idx.clamp(
      0,
      SubtitleStyle.options.length - 1,
    )];
  }

  Future<SubtitleColor> getCurrentColor() async {
    final idx = await getColorIndex();
    return SubtitleColor.options[idx.clamp(
      0,
      SubtitleColor.options.length - 1,
    )];
  }

  Future<SubtitleBackground> getCurrentBg() async {
    final idx = await getBgIndex();
    return SubtitleBackground.options[idx.clamp(
      0,
      SubtitleBackground.options.length - 1,
    )];
  }

  Future<SubtitleOutlineColor> getCurrentOutlineColor() async {
    final idx = await getOutlineColorIndex();
    return SubtitleOutlineColor.options[idx.clamp(
      0,
      SubtitleOutlineColor.options.length - 1,
    )];
  }

  Future<SubtitleElevation> getCurrentElevation() async {
    final idx = await getElevationIndex();
    return SubtitleElevation.options[idx.clamp(
      0,
      SubtitleElevation.options.length - 1,
    )];
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
      outlineColorIndex:
          _prefs!.getInt(_keyOutlineColorIndex) ??
          SubtitleOutlineColor.defaultIndex,
      elevationIndex:
          _prefs!.getInt(_keyElevationIndex) ?? SubtitleElevation.defaultIndex,
      bold: _prefs!.getBool(_keyBold) ?? defaultBold,
      syncOffsetMs: _syncOffsetMs,
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
    await _prefs!.setInt(
      _keyOutlineColorIndex,
      SubtitleOutlineColor.defaultIndex,
    );
    await _prefs!.setInt(_keyElevationIndex, SubtitleElevation.defaultIndex);
    await _prefs!.setBool(_keyBold, defaultBold);
    // Sync offset is in-memory and per-subtitle, not a persisted style.
    resetSyncOffset();
    await SubtitleFontService.instance.resetToDefault();
  }

  /// Check if settings are at defaults
  Future<bool> isDefault() async {
    final data = await loadAll();
    return data.sizeIndex == SubtitleSize.defaultIndex &&
        data.styleIndex == SubtitleStyle.defaultIndex &&
        data.colorIndex == SubtitleColor.defaultIndex &&
        data.bgIndex == SubtitleBackground.defaultIndex &&
        data.outlineColorIndex == SubtitleOutlineColor.defaultIndex &&
        data.elevationIndex == SubtitleElevation.defaultIndex &&
        data.bold == defaultBold &&
        data.fontIndex == SubtitleFont.defaultIndex &&
        data.syncOffsetMs == 0;
  }
}

/// Holds all subtitle settings data
class SubtitleSettingsData {
  final int sizeIndex;
  final int styleIndex;
  final int colorIndex;
  final int bgIndex;
  final int outlineColorIndex;
  final int elevationIndex;
  final bool bold;
  final int fontIndex;
  final String? fontFamily;
  final String fontLabel;
  final int syncOffsetMs;

  const SubtitleSettingsData({
    required this.sizeIndex,
    required this.styleIndex,
    required this.colorIndex,
    required this.bgIndex,
    this.outlineColorIndex = 0,
    this.elevationIndex = SubtitleElevation.defaultIndex,
    this.bold = false,
    this.fontIndex = 0,
    this.fontFamily,
    this.fontLabel = 'Default',
    this.syncOffsetMs = 0,
  });

  SubtitleSize get size =>
      SubtitleSize.options[sizeIndex.clamp(0, SubtitleSize.options.length - 1)];

  SubtitleStyle get style =>
      SubtitleStyle.options[styleIndex.clamp(
        0,
        SubtitleStyle.options.length - 1,
      )];

  SubtitleColor get color =>
      SubtitleColor.options[colorIndex.clamp(
        0,
        SubtitleColor.options.length - 1,
      )];

  SubtitleBackground get background =>
      SubtitleBackground.options[bgIndex.clamp(
        0,
        SubtitleBackground.options.length - 1,
      )];

  SubtitleOutlineColor get outlineColor =>
      SubtitleOutlineColor.options[outlineColorIndex.clamp(
        0,
        SubtitleOutlineColor.options.length - 1,
      )];

  SubtitleElevation get elevation =>
      SubtitleElevation.options[elevationIndex.clamp(
        0,
        SubtitleElevation.options.length - 1,
      )];

  /// Get shadows with outline color applied (null color = auto/keep original)
  List<Shadow>? get resolvedShadows {
    final shadows = style.shadows;
    if (shadows == null) return null;
    final oc = outlineColor.color;
    if (oc == null) return shadows; // Auto
    return shadows
        .map(
          (s) => Shadow(offset: s.offset, blurRadius: s.blurRadius, color: oc),
        )
        .toList();
  }

  SubtitleFont get font => SubtitleFont(
    id: fontIndex.toString(),
    label: fontLabel,
    fontFamily: fontFamily,
  );

  String get syncOffsetLabel {
    if (syncOffsetMs == 0) return '0';
    final sign = syncOffsetMs > 0 ? '+' : '';
    final abs = syncOffsetMs.abs();
    if (abs >= 1000 && abs % 1000 == 0) return '$sign${syncOffsetMs ~/ 1000}s';
    if (abs >= 1000) return '$sign${(syncOffsetMs / 1000).toStringAsFixed(1)}s';
    return '$sign${syncOffsetMs}ms';
  }

  Color get syncOffsetColor {
    final abs = syncOffsetMs.abs();
    if (abs == 0) return const Color(0xFF4CAF50);
    if (abs <= 500) return const Color(0xFF8BC34A);
    if (abs <= 1000) return const Color(0xFFCDDC39);
    if (abs <= 2000) return const Color(0xFFFFC107);
    if (abs <= 3000) return const Color(0xFFFF9800);
    return const Color(0xFFFF5722);
  }

  /// Subtitle families that ship a REAL bold face, so [FontWeight.w700] alone
  /// renders true bold glyphs.
  ///
  /// Everything else in the picker — Open Sans, Inter, Lato, Poppins, Nunito,
  /// Merriweather, Source Serif, Fira Mono, Noto Sans — is declared with a
  /// single Regular asset in pubspec.yaml, and every user-imported font is one
  /// file by definition. Flutter silently ignores [FontWeight] for those, which
  /// is what synthetic emboldening exists to cover.
  static const Set<String> _familiesWithBoldAsset = {'Roboto'};

  /// Whether [fontFamily] can be bolded by asking for the weight.
  bool get hasRealBoldFace {
    final family = fontFamily;
    // No family = the platform's own UI font (Roboto / SF / Segoe), all of
    // which carry a bold face.
    if (family == null || family.isEmpty) return true;
    return _familiesWithBoldAsset.contains(family);
  }

  /// Stroke width that emboldens a single-weight font at [fontSizePx].
  ///
  /// ~5.5% of the em is the range real bold faces sit in relative to their
  /// regular. Clamped so tiny text doesn't lose its counters and giant text
  /// doesn't turn into slabs.
  double _emboldenStroke(double fontSizePx) =>
      (fontSizePx * 0.055).clamp(0.8, 3.2);

  /// The size the edge-style offsets were tuned at (Medium). Offsets and
  /// blurs scale linearly from here, so the ring keeps its PROPORTION at
  /// every size — a fixed 1.5px ring on a Giant 90px glyph was a hairline
  /// that read as blur, not an outline.
  static const double _edgeReferenceSizePx = 42;

  /// The edge shadows scaled by [scale], then pushed [expand] further out
  /// along their own direction.
  ///
  /// Emboldening grows the glyph by half the stroke, which would otherwise eat
  /// the rim from the inside and leave a thin, patchy outline. Moving each
  /// shadow out by the same amount keeps the rim's VISIBLE thickness the same
  /// whether bold is on or off.
  List<Shadow>? _edgeShadows(double expand, {double scale = 1}) {
    final base = resolvedShadows;
    if (base == null || (expand <= 0 && scale == 1)) return base;
    return [
      for (final s in base)
        Shadow(
          offset: s.offset.distance == 0
              ? s.offset
              : s.offset * scale + (s.offset / s.offset.distance) * expand,
          blurRadius: s.blurRadius * scale,
          color: s.color,
        ),
    ];
  }

  /// Build the subtitle [TextStyle] — the ONE place subtitle text is styled,
  /// so the player and every preview agree. [fontSizePx] overrides the
  /// configured size for previews that render at a fraction of it; the
  /// emboldening scales with whatever size is actually drawn.
  ///
  /// Bold is done two different ways ON PURPOSE:
  ///  - a font with a real bold face just gets [FontWeight.w700] — one
  ///    rasterisation of glyphs a type designer drew, which is as crisp as
  ///    text gets;
  ///  - a single-weight font gets a STROKE around the glyph outline instead.
  ///    Still one rasterisation, uniformly thickened in every direction.
  ///
  /// The stroke lives in [TextStyle.foreground], which is mutually exclusive
  /// with [TextStyle.color] — so the fill is supplied as a zero-offset,
  /// zero-blur shadow underneath it. That is the only way to get fill AND
  /// stroke out of a single TextStyle, and it's why the fill is a "shadow"
  /// that casts nothing.
  ///
  /// [includeBackground] is for callers that already paint [background]
  /// themselves (the tracks-sheet preview wraps the sample in a chip of that
  /// colour). The background alphas are TRANSLUCENT, so painting the same
  /// colour twice darkens the band behind the glyphs relative to the chip.
  TextStyle buildTextStyle({
    double? fontSizePx,
    bool includeBackground = true,
  }) {
    final resolvedSize = fontSizePx ?? size.sizePx;
    final embolden = bold && !hasRealBoldFace;
    final stroke = embolden ? _emboldenStroke(resolvedSize) : 0.0;
    final edges = _edgeShadows(
      stroke / 2,
      scale: resolvedSize / _edgeReferenceSizePx,
    );
    // Null, not an empty list, when there is nothing to paint — so an
    // edge-style of "None" with bold off stays byte-identical to before.
    final shadows = <Shadow>[
      ...?edges,
      if (embolden) Shadow(color: color.color),
    ];
    return TextStyle(
      fontSize: resolvedSize,
      color: embolden ? null : color.color,
      foreground: embolden
          ? (Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke
              // Round joins keep corners from spiking out at heavy strokes.
              ..strokeJoin = StrokeJoin.round
              ..strokeCap = StrokeCap.round
              ..color = color.color)
          : null,
      fontWeight: bold && !embolden ? FontWeight.w700 : FontWeight.w400,
      // Painted in list order, first furthest back: rim, then fill, then the
      // glyph itself (the stroke) on top.
      shadows: shadows.isEmpty ? null : shadows,
      backgroundColor: includeBackground ? background.color : null,
      fontFamily: fontFamily,
    );
  }

  SubtitleSettingsData copyWith({
    int? sizeIndex,
    int? styleIndex,
    int? colorIndex,
    int? bgIndex,
    int? outlineColorIndex,
    int? elevationIndex,
    bool? bold,
    int? fontIndex,
    String? fontFamily,
    String? fontLabel,
    int? syncOffsetMs,
  }) {
    return SubtitleSettingsData(
      sizeIndex: sizeIndex ?? this.sizeIndex,
      styleIndex: styleIndex ?? this.styleIndex,
      colorIndex: colorIndex ?? this.colorIndex,
      bgIndex: bgIndex ?? this.bgIndex,
      outlineColorIndex: outlineColorIndex ?? this.outlineColorIndex,
      elevationIndex: elevationIndex ?? this.elevationIndex,
      bold: bold ?? this.bold,
      fontIndex: fontIndex ?? this.fontIndex,
      fontFamily: fontFamily ?? this.fontFamily,
      fontLabel: fontLabel ?? this.fontLabel,
      syncOffsetMs: syncOffsetMs ?? this.syncOffsetMs,
    );
  }
}

/// One remembered sync: display time = file time × [scale] + [offsetMs].
class SubtitleSyncMemoryEntry {
  final String identity;
  final int offsetMs;
  final double scale;

  const SubtitleSyncMemoryEntry({
    required this.identity,
    required this.offsetMs,
    this.scale = 1.0,
  });
}
