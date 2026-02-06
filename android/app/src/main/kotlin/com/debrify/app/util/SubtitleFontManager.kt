package com.debrify.app.util

import android.content.Context
import android.graphics.Typeface
import java.io.File

/**
 * Built-in font options for subtitles.
 */
data class SubtitleFontOption(
    val id: String,
    val label: String,
    val typefaceStyle: Int = Typeface.NORMAL,
    val fontFamily: String? = null,
    val assetPath: String? = null // Path to bundled font in assets/fonts/
) {
    val isCustom: Boolean get() = id == "custom"
    val isDefault: Boolean get() = id == "default"
    val isBundled: Boolean get() = assetPath != null
}

/**
 * Manages custom subtitle fonts for Android players.
 * Handles loading bundled and custom TTF/OTF fonts and providing Typeface instances.
 */
object SubtitleFontManager {

    private const val PREFS_NAME = "debrify_subtitle_settings"
    private const val KEY_FONT_INDEX = "subtitle_font_index"
    private const val KEY_CUSTOM_FONT_PATH = "subtitle_custom_font_path"
    private const val KEY_CUSTOM_FONT_NAME = "subtitle_custom_font_name"

    const val DEFAULT_FONT_INDEX = 0

    // 10 bundled fonts + custom option (matches Flutter's SubtitleFont.builtInOptions)
    val FONT_OPTIONS = listOf(
        SubtitleFontOption("default", "Default"),
        SubtitleFontOption("roboto", "Roboto", assetPath = "fonts/Roboto-Regular.ttf"),
        SubtitleFontOption("opensans", "Open Sans", assetPath = "fonts/OpenSans-Regular.ttf"),
        SubtitleFontOption("inter", "Inter", assetPath = "fonts/Inter-Regular.ttf"),
        SubtitleFontOption("lato", "Lato", assetPath = "fonts/Lato-Regular.ttf"),
        SubtitleFontOption("poppins", "Poppins", assetPath = "fonts/Poppins-Regular.ttf"),
        SubtitleFontOption("nunito", "Nunito", assetPath = "fonts/Nunito-Regular.ttf"),
        SubtitleFontOption("merriweather", "Merriweather", assetPath = "fonts/Merriweather-Regular.ttf"),
        SubtitleFontOption("sourceserif", "Source Serif", assetPath = "fonts/SourceSerifPro-Regular.ttf"),
        SubtitleFontOption("firamono", "Fira Mono", assetPath = "fonts/FiraMono-Regular.ttf"),
        SubtitleFontOption("notosans", "Noto Sans", assetPath = "fonts/NotoSans-Regular.ttf"),
        SubtitleFontOption("custom", "Custom Font")
    )

    // Cached typefaces
    private var cachedCustomTypeface: Typeface? = null
    private var cachedCustomFontPath: String? = null
    private val cachedBundledTypefaces = mutableMapOf<String, Typeface>()

    private fun getPrefs(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /**
     * Get current font index.
     */
    @JvmStatic
    fun getFontIndex(context: Context): Int {
        return getPrefs(context).getInt(KEY_FONT_INDEX, DEFAULT_FONT_INDEX)
    }

    /**
     * Set font index.
     */
    @JvmStatic
    fun setFontIndex(context: Context, index: Int) {
        getPrefs(context).edit()
            .putInt(KEY_FONT_INDEX, index.coerceIn(0, FONT_OPTIONS.size - 1))
            .apply()
    }

    /**
     * Get custom font file path.
     */
    @JvmStatic
    fun getCustomFontPath(context: Context): String? {
        return getPrefs(context).getString(KEY_CUSTOM_FONT_PATH, null)
    }

    /**
     * Get custom font display name.
     */
    @JvmStatic
    fun getCustomFontName(context: Context): String? {
        return getPrefs(context).getString(KEY_CUSTOM_FONT_NAME, null)
    }

    /**
     * Get current font option.
     */
    @JvmStatic
    fun getCurrentFont(context: Context): SubtitleFontOption {
        val idx = getFontIndex(context).coerceIn(0, FONT_OPTIONS.size - 1)
        return FONT_OPTIONS[idx]
    }

    /**
     * Get display label for current font.
     */
    @JvmStatic
    fun getCurrentFontLabel(context: Context): String {
        val font = getCurrentFont(context)
        if (font.isCustom) {
            return getCustomFontName(context) ?: "Custom Font"
        }
        return font.label
    }

    /**
     * Get Typeface for current font settings.
     */
    @JvmStatic
    fun getTypeface(context: Context): Typeface {
        val font = getCurrentFont(context)

        // Handle custom font
        if (font.isCustom) {
            val customTypeface = loadCustomTypeface(context)
            if (customTypeface != null) {
                return customTypeface
            }
            // Fallback to default if custom font not available
            return Typeface.create("sans-serif", Typeface.NORMAL)
        }

        // Handle bundled font from assets
        if (font.isBundled) {
            val bundledTypeface = loadBundledTypeface(context, font)
            if (bundledTypeface != null) {
                return bundledTypeface
            }
            // Fallback to default if bundled font fails to load
            return Typeface.create("sans-serif", Typeface.NORMAL)
        }

        // Default
        return Typeface.create("sans-serif", Typeface.NORMAL)
    }

    /**
     * Load bundled typeface from assets.
     */
    private fun loadBundledTypeface(context: Context, font: SubtitleFontOption): Typeface? {
        val assetPath = font.assetPath ?: return null

        // Return cached typeface if available
        cachedBundledTypefaces[assetPath]?.let { return it }

        return try {
            val typeface = Typeface.createFromAsset(context.assets, assetPath)
            cachedBundledTypefaces[assetPath] = typeface
            typeface
        } catch (e: Exception) {
            android.util.Log.e("SubtitleFontManager", "Failed to load bundled font $assetPath: ${e.message}")
            null
        }
    }

    /**
     * Load custom typeface from file.
     */
    private fun loadCustomTypeface(context: Context): Typeface? {
        val fontPath = getCustomFontPath(context) ?: return null

        // Return cached typeface if path matches
        if (fontPath == cachedCustomFontPath && cachedCustomTypeface != null) {
            return cachedCustomTypeface
        }

        return try {
            val fontFile = File(fontPath)
            if (!fontFile.exists()) {
                null
            } else {
                val typeface = Typeface.createFromFile(fontFile)
                cachedCustomTypeface = typeface
                cachedCustomFontPath = fontPath
                typeface
            }
        } catch (e: Exception) {
            android.util.Log.e("SubtitleFontManager", "Failed to load custom font: ${e.message}")
            null
        }
    }

    /**
     * Check if custom font is available.
     */
    @JvmStatic
    fun hasCustomFont(context: Context): Boolean {
        val path = getCustomFontPath(context) ?: return false
        return File(path).exists()
    }

    /**
     * Cycle to next font option.
     */
    @JvmStatic
    fun cycleFontUp(context: Context): Int {
        val options = getAvailableOptionIndices(context)
        val current = getFontIndex(context)
        val currentInOptions = options.indexOf(current).takeIf { it >= 0 } ?: 0
        val nextIndex = (currentInOptions + 1) % options.size
        val newFontIndex = options[nextIndex]
        setFontIndex(context, newFontIndex)
        return newFontIndex
    }

    /**
     * Cycle to previous font option.
     */
    @JvmStatic
    fun cycleFontDown(context: Context): Int {
        val options = getAvailableOptionIndices(context)
        val current = getFontIndex(context)
        val currentInOptions = options.indexOf(current).takeIf { it >= 0 } ?: 0
        val prevIndex = if (currentInOptions == 0) options.size - 1 else currentInOptions - 1
        val newFontIndex = options[prevIndex]
        setFontIndex(context, newFontIndex)
        return newFontIndex
    }

    /**
     * Get available font option indices (excludes custom if not set).
     */
    private fun getAvailableOptionIndices(context: Context): List<Int> {
        val hasCustom = hasCustomFont(context)
        return FONT_OPTIONS.indices.filter { i ->
            val font = FONT_OPTIONS[i]
            !font.isCustom || hasCustom
        }
    }

    /**
     * Reset font to default.
     */
    @JvmStatic
    fun resetToDefault(context: Context) {
        setFontIndex(context, DEFAULT_FONT_INDEX)
    }

    /**
     * Clear font caches (call when font file changes).
     */
    @JvmStatic
    fun clearCache() {
        cachedCustomTypeface = null
        cachedCustomFontPath = null
        cachedBundledTypefaces.clear()
    }

    /**
     * Set custom font from external path (e.g., from Flutter).
     * This stores the path in SharedPreferences so it persists for future use.
     */
    @JvmStatic
    fun setCustomFontFromPath(context: Context, fontPath: String?, fontName: String? = null) {
        if (fontPath == null) {
            return
        }

        val file = File(fontPath)
        if (!file.exists()) {
            android.util.Log.w("SubtitleFontManager", "Custom font path does not exist: $fontPath")
            return
        }

        // Store the custom font path and name
        val displayName = fontName ?: extractFontName(fontPath)
        getPrefs(context).edit()
            .putString(KEY_CUSTOM_FONT_PATH, fontPath)
            .putString(KEY_CUSTOM_FONT_NAME, displayName)
            .apply()

        // Clear cache to force reload
        cachedCustomTypeface = null
        cachedCustomFontPath = null

        android.util.Log.d("SubtitleFontManager", "Set custom font: $displayName from $fontPath")
    }

    /**
     * Extract a display name from font file path.
     */
    private fun extractFontName(fontPath: String): String {
        val fileName = File(fontPath).nameWithoutExtension
        // Remove common prefixes like "custom_123456789_"
        val cleanName = fileName.replace(Regex("^custom_\\d+_"), "")
        // Replace separators with spaces and capitalize words
        return cleanName
            .replace(Regex("[-_]"), " ")
            .split(" ")
            .joinToString(" ") { word ->
                word.replaceFirstChar { it.uppercase() }
            }
    }

    /**
     * Check if a custom font path is valid and set it if so.
     * Returns true if the font was set successfully.
     */
    @JvmStatic
    fun applyCustomFontIfValid(context: Context, fontPath: String?, fontName: String? = null): Boolean {
        if (fontPath.isNullOrEmpty()) {
            return false
        }

        val file = File(fontPath)
        if (!file.exists()) {
            return false
        }

        setCustomFontFromPath(context, fontPath, fontName)

        // Also set the font index to "custom" (last option)
        val customIndex = FONT_OPTIONS.indexOfFirst { it.isCustom }
        if (customIndex >= 0) {
            setFontIndex(context, customIndex)
        }

        return true
    }
}
