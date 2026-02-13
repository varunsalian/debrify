package com.debrify.app.util

import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface
import androidx.media3.ui.CaptionStyleCompat

/**
 * Subtitle customization settings manager.
 * Handles persistence and provides styling options for subtitle overlay.
 */
object SubtitleSettings {

    private const val PREFS_NAME = "debrify_subtitle_settings"
    private const val FLUTTER_PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_SIZE_INDEX = "subtitle_size_index"
    private const val KEY_STYLE_INDEX = "subtitle_style_index"
    private const val KEY_COLOR_INDEX = "subtitle_color_index"
    private const val KEY_BG_INDEX = "subtitle_bg_index"
    private const val KEY_OUTLINE_COLOR_INDEX = "subtitle_outline_color_index"
    private const val KEY_ELEVATION_INDEX = "subtitle_elevation_index"
    private const val KEY_DEFAULT_SUBTITLE_LANGUAGE = "flutter.player_default_subtitle_language"
    private const val KEY_DEFAULT_AUDIO_LANGUAGE = "flutter.player_default_audio_language"

    // Default indices
    const val DEFAULT_SIZE_INDEX = 2      // Medium
    const val DEFAULT_STYLE_INDEX = 1     // Outline
    const val DEFAULT_COLOR_INDEX = 0     // White
    const val DEFAULT_BG_INDEX = 0        // None
    const val DEFAULT_OUTLINE_COLOR_INDEX = 0  // Auto
    const val DEFAULT_ELEVATION_INDEX = 0      // Bottom

    // Size options (in SP)
    data class SizeOption(val label: String, val sizeSp: Float)
    val SIZE_OPTIONS = listOf(
        SizeOption("Tiny", 12f),
        SizeOption("Small", 14f),
        SizeOption("Medium", 16f),
        SizeOption("Large", 20f),
        SizeOption("X-Large", 24f),
        SizeOption("Huge", 28f),
        SizeOption("Giant", 32f)
    )

    // Edge style options
    data class StyleOption(val label: String, val edgeType: Int)
    val STYLE_OPTIONS = listOf(
        StyleOption("None", CaptionStyleCompat.EDGE_TYPE_NONE),
        StyleOption("Outline", CaptionStyleCompat.EDGE_TYPE_OUTLINE),
        StyleOption("Shadow", CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW),
        StyleOption("Raised", CaptionStyleCompat.EDGE_TYPE_RAISED),
        StyleOption("Depressed", CaptionStyleCompat.EDGE_TYPE_DEPRESSED)
    )

    // Text color options
    data class ColorOption(val label: String, val color: Int)
    val COLOR_OPTIONS = listOf(
        ColorOption("White", Color.WHITE),
        ColorOption("Yellow", Color.parseColor("#FFFF00")),
        ColorOption("Cyan", Color.parseColor("#00FFFF")),
        ColorOption("Green", Color.parseColor("#00FF00")),
        ColorOption("Magenta", Color.parseColor("#FF00FF")),
        ColorOption("Red", Color.parseColor("#FF4444")),
        ColorOption("Blue", Color.parseColor("#4488FF")),
        ColorOption("Orange", Color.parseColor("#FF8800"))
    )

    // Background options
    data class BgOption(val label: String, val color: Int)
    val BG_OPTIONS = listOf(
        BgOption("None", Color.TRANSPARENT),
        BgOption("Light", Color.parseColor("#40000000")),
        BgOption("Medium", Color.parseColor("#80000000")),
        BgOption("Dark", Color.parseColor("#B3000000")),
        BgOption("Solid", Color.parseColor("#E6000000"))
    )

    // Outline/edge color options (null color = auto contrast-based)
    data class OutlineColorOption(val label: String, val color: Int?, val isAuto: Boolean = false)
    val OUTLINE_COLOR_OPTIONS = listOf(
        OutlineColorOption("Auto", null, isAuto = true),
        OutlineColorOption("Black", Color.BLACK),
        OutlineColorOption("White", Color.WHITE),
        OutlineColorOption("Yellow", Color.parseColor("#FFFF00")),
        OutlineColorOption("Cyan", Color.parseColor("#00FFFF")),
        OutlineColorOption("Green", Color.parseColor("#00FF00")),
        OutlineColorOption("Magenta", Color.parseColor("#FF00FF")),
        OutlineColorOption("Red", Color.parseColor("#FF4444")),
        OutlineColorOption("Blue", Color.parseColor("#4488FF")),
        OutlineColorOption("Orange", Color.parseColor("#FF8800"))
    )

    // Elevation (vertical position) options — fraction of view height for bottom padding
    data class ElevationOption(val label: String, val paddingFraction: Float)
    val ELEVATION_OPTIONS = listOf(
        ElevationOption("Bottom", 0.0f),
        ElevationOption("Low", 0.04f),
        ElevationOption("Medium", 0.08f),
        ElevationOption("High", 0.15f),
        ElevationOption("Higher", 0.25f)
    )

    private fun getPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private fun getFlutterPrefs(context: Context): SharedPreferences {
        return context.getSharedPreferences(FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
    }

    /**
     * Get the default subtitle language from Flutter settings.
     * Returns language code (e.g., "en", "es"), "off" for disabled, or null for no preference.
     */
    @JvmStatic
    fun getDefaultSubtitleLanguage(context: Context): String? {
        return getFlutterPrefs(context).getString(KEY_DEFAULT_SUBTITLE_LANGUAGE, null)
    }

    /**
     * Get the default audio language from Flutter settings.
     * Returns language code (e.g., "en", "es") or null for no preference.
     */
    @JvmStatic
    fun getDefaultAudioLanguage(context: Context): String? {
        return getFlutterPrefs(context).getString(KEY_DEFAULT_AUDIO_LANGUAGE, null)
    }

    // Getters
    @JvmStatic
    fun getSizeIndex(context: Context): Int {
        return getPrefs(context).getInt(KEY_SIZE_INDEX, DEFAULT_SIZE_INDEX)
    }

    @JvmStatic
    fun getStyleIndex(context: Context): Int {
        return getPrefs(context).getInt(KEY_STYLE_INDEX, DEFAULT_STYLE_INDEX)
    }

    @JvmStatic
    fun getColorIndex(context: Context): Int {
        return getPrefs(context).getInt(KEY_COLOR_INDEX, DEFAULT_COLOR_INDEX)
    }

    @JvmStatic
    fun getBgIndex(context: Context): Int {
        return getPrefs(context).getInt(KEY_BG_INDEX, DEFAULT_BG_INDEX)
    }

    @JvmStatic
    fun getOutlineColorIndex(context: Context): Int {
        return getPrefs(context).getInt(KEY_OUTLINE_COLOR_INDEX, DEFAULT_OUTLINE_COLOR_INDEX)
    }

    @JvmStatic
    fun getElevationIndex(context: Context): Int {
        return getPrefs(context).getInt(KEY_ELEVATION_INDEX, DEFAULT_ELEVATION_INDEX)
    }

    // Setters
    @JvmStatic
    fun setSizeIndex(context: Context, index: Int) {
        getPrefs(context).edit().putInt(KEY_SIZE_INDEX, index.coerceIn(0, SIZE_OPTIONS.size - 1)).apply()
    }

    @JvmStatic
    fun setStyleIndex(context: Context, index: Int) {
        getPrefs(context).edit().putInt(KEY_STYLE_INDEX, index.coerceIn(0, STYLE_OPTIONS.size - 1)).apply()
    }

    @JvmStatic
    fun setColorIndex(context: Context, index: Int) {
        getPrefs(context).edit().putInt(KEY_COLOR_INDEX, index.coerceIn(0, COLOR_OPTIONS.size - 1)).apply()
    }

    @JvmStatic
    fun setBgIndex(context: Context, index: Int) {
        getPrefs(context).edit().putInt(KEY_BG_INDEX, index.coerceIn(0, BG_OPTIONS.size - 1)).apply()
    }

    @JvmStatic
    fun setOutlineColorIndex(context: Context, index: Int) {
        getPrefs(context).edit().putInt(KEY_OUTLINE_COLOR_INDEX, index.coerceIn(0, OUTLINE_COLOR_OPTIONS.size - 1)).apply()
    }

    @JvmStatic
    fun setElevationIndex(context: Context, index: Int) {
        getPrefs(context).edit().putInt(KEY_ELEVATION_INDEX, index.coerceIn(0, ELEVATION_OPTIONS.size - 1)).apply()
    }

    // Get current values
    @JvmStatic
    fun getCurrentSize(context: Context): SizeOption = SIZE_OPTIONS[getSizeIndex(context).coerceIn(0, SIZE_OPTIONS.size - 1)]

    @JvmStatic
    fun getCurrentStyle(context: Context): StyleOption = STYLE_OPTIONS[getStyleIndex(context).coerceIn(0, STYLE_OPTIONS.size - 1)]

    @JvmStatic
    fun getCurrentColor(context: Context): ColorOption = COLOR_OPTIONS[getColorIndex(context).coerceIn(0, COLOR_OPTIONS.size - 1)]

    @JvmStatic
    fun getCurrentBg(context: Context): BgOption = BG_OPTIONS[getBgIndex(context).coerceIn(0, BG_OPTIONS.size - 1)]

    @JvmStatic
    fun getCurrentOutlineColor(context: Context): OutlineColorOption = OUTLINE_COLOR_OPTIONS[getOutlineColorIndex(context).coerceIn(0, OUTLINE_COLOR_OPTIONS.size - 1)]

    @JvmStatic
    fun getCurrentElevation(context: Context): ElevationOption = ELEVATION_OPTIONS[getElevationIndex(context).coerceIn(0, ELEVATION_OPTIONS.size - 1)]

    // Cycle functions (for up/down navigation)
    @JvmStatic
    fun cycleSizeUp(context: Context): Int {
        val newIndex = (getSizeIndex(context) + 1) % SIZE_OPTIONS.size
        setSizeIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleSizeDown(context: Context): Int {
        val current = getSizeIndex(context)
        val newIndex = if (current == 0) SIZE_OPTIONS.size - 1 else current - 1
        setSizeIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleStyleUp(context: Context): Int {
        val newIndex = (getStyleIndex(context) + 1) % STYLE_OPTIONS.size
        setStyleIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleStyleDown(context: Context): Int {
        val current = getStyleIndex(context)
        val newIndex = if (current == 0) STYLE_OPTIONS.size - 1 else current - 1
        setStyleIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleColorUp(context: Context): Int {
        val newIndex = (getColorIndex(context) + 1) % COLOR_OPTIONS.size
        setColorIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleColorDown(context: Context): Int {
        val current = getColorIndex(context)
        val newIndex = if (current == 0) COLOR_OPTIONS.size - 1 else current - 1
        setColorIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleBgUp(context: Context): Int {
        val newIndex = (getBgIndex(context) + 1) % BG_OPTIONS.size
        setBgIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleBgDown(context: Context): Int {
        val current = getBgIndex(context)
        val newIndex = if (current == 0) BG_OPTIONS.size - 1 else current - 1
        setBgIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleOutlineColorUp(context: Context): Int {
        val newIndex = (getOutlineColorIndex(context) + 1) % OUTLINE_COLOR_OPTIONS.size
        setOutlineColorIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleOutlineColorDown(context: Context): Int {
        val current = getOutlineColorIndex(context)
        val newIndex = if (current == 0) OUTLINE_COLOR_OPTIONS.size - 1 else current - 1
        setOutlineColorIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleElevationUp(context: Context): Int {
        val newIndex = (getElevationIndex(context) + 1) % ELEVATION_OPTIONS.size
        setElevationIndex(context, newIndex)
        return newIndex
    }

    @JvmStatic
    fun cycleElevationDown(context: Context): Int {
        val current = getElevationIndex(context)
        val newIndex = if (current == 0) ELEVATION_OPTIONS.size - 1 else current - 1
        setElevationIndex(context, newIndex)
        return newIndex
    }

    /**
     * Reset all subtitle settings to defaults.
     */
    @JvmStatic
    fun resetToDefaults(context: Context) {
        getPrefs(context).edit()
            .putInt(KEY_SIZE_INDEX, DEFAULT_SIZE_INDEX)
            .putInt(KEY_STYLE_INDEX, DEFAULT_STYLE_INDEX)
            .putInt(KEY_COLOR_INDEX, DEFAULT_COLOR_INDEX)
            .putInt(KEY_BG_INDEX, DEFAULT_BG_INDEX)
            .putInt(KEY_OUTLINE_COLOR_INDEX, DEFAULT_OUTLINE_COLOR_INDEX)
            .putInt(KEY_ELEVATION_INDEX, DEFAULT_ELEVATION_INDEX)
            .apply()
    }

    /**
     * Check if current settings match defaults.
     */
    @JvmStatic
    fun isDefault(context: Context): Boolean {
        return getSizeIndex(context) == DEFAULT_SIZE_INDEX &&
                getStyleIndex(context) == DEFAULT_STYLE_INDEX &&
                getColorIndex(context) == DEFAULT_COLOR_INDEX &&
                getBgIndex(context) == DEFAULT_BG_INDEX &&
                getOutlineColorIndex(context) == DEFAULT_OUTLINE_COLOR_INDEX &&
                getElevationIndex(context) == DEFAULT_ELEVATION_INDEX
    }

    /**
     * Build a CaptionStyleCompat from current settings.
     */
    @JvmStatic
    fun buildCaptionStyle(context: Context): CaptionStyleCompat {
        val colorOption = getCurrentColor(context)
        val styleOption = getCurrentStyle(context)
        val bgOption = getCurrentBg(context)
        val outlineColorOption = getCurrentOutlineColor(context)

        // Determine edge color: use stored value or auto-calculate from text color
        val edgeColor = if (outlineColorOption.isAuto || outlineColorOption.color == null) {
            when {
                colorOption.color == Color.WHITE -> Color.BLACK
                colorOption.color == Color.parseColor("#FFFF00") -> Color.BLACK  // Yellow
                colorOption.color == Color.parseColor("#00FFFF") -> Color.BLACK  // Cyan
                else -> Color.parseColor("#CC000000")  // Darker edge for colored text
            }
        } else {
            outlineColorOption.color ?: Color.BLACK
        }

        // Get typeface from font manager
        val typeface = SubtitleFontManager.getTypeface(context)

        return CaptionStyleCompat(
            colorOption.color,       // foreground (text color)
            bgOption.color,          // background
            Color.TRANSPARENT,       // window color
            styleOption.edgeType,    // edge type
            edgeColor,               // edge color
            typeface                 // custom or default typeface
        )
    }

    /**
     * Get the font size in SP from current settings.
     */
    @JvmStatic
    fun getFontSizeSp(context: Context): Float {
        return getCurrentSize(context).sizeSp
    }

    /**
     * Get the elevation bottom padding fraction from current settings.
     */
    @JvmStatic
    fun getElevationPaddingFraction(context: Context): Float {
        return getCurrentElevation(context).paddingFraction
    }
}
