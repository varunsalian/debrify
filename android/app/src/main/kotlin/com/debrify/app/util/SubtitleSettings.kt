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
    private const val KEY_DEFAULT_SUBTITLE_LANGUAGE = "flutter.player_default_subtitle_language"

    // Default indices
    const val DEFAULT_SIZE_INDEX = 2      // Medium
    const val DEFAULT_STYLE_INDEX = 1     // Outline
    const val DEFAULT_COLOR_INDEX = 0     // White
    const val DEFAULT_BG_INDEX = 0        // None

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

    // Get current values
    @JvmStatic
    fun getCurrentSize(context: Context): SizeOption = SIZE_OPTIONS[getSizeIndex(context).coerceIn(0, SIZE_OPTIONS.size - 1)]

    @JvmStatic
    fun getCurrentStyle(context: Context): StyleOption = STYLE_OPTIONS[getStyleIndex(context).coerceIn(0, STYLE_OPTIONS.size - 1)]

    @JvmStatic
    fun getCurrentColor(context: Context): ColorOption = COLOR_OPTIONS[getColorIndex(context).coerceIn(0, COLOR_OPTIONS.size - 1)]

    @JvmStatic
    fun getCurrentBg(context: Context): BgOption = BG_OPTIONS[getBgIndex(context).coerceIn(0, BG_OPTIONS.size - 1)]

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
                getBgIndex(context) == DEFAULT_BG_INDEX
    }

    /**
     * Build a CaptionStyleCompat from current settings.
     */
    @JvmStatic
    fun buildCaptionStyle(context: Context): CaptionStyleCompat {
        val colorOption = getCurrentColor(context)
        val styleOption = getCurrentStyle(context)
        val bgOption = getCurrentBg(context)

        // Determine edge color based on text color (contrast)
        val edgeColor = when {
            colorOption.color == Color.WHITE -> Color.BLACK
            colorOption.color == Color.parseColor("#FFFF00") -> Color.BLACK  // Yellow
            colorOption.color == Color.parseColor("#00FFFF") -> Color.BLACK  // Cyan
            else -> Color.parseColor("#CC000000")  // Darker edge for colored text
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
}
