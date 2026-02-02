package com.debrify.app.subtitle

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Represents a subtitle track from a Stremio addon.
 */
data class StremioSubtitle(
    val id: String,
    val url: String,
    val lang: String,
    val label: String?,
    val source: String
) {
    /**
     * Display name for UI (label or formatted language)
     */
    val displayName: String
        get() = label?.takeIf { it.isNotEmpty() } ?: formatLanguageCode(lang)

    companion object {
        private val languageNames = mapOf(
            // ISO 639-2/B codes (3-letter)
            "eng" to "English", "spa" to "Spanish", "por" to "Portuguese",
            "fra" to "French", "deu" to "German", "ita" to "Italian",
            "rus" to "Russian", "jpn" to "Japanese", "kor" to "Korean",
            "zho" to "Chinese", "chi" to "Chinese", "ara" to "Arabic",
            "hin" to "Hindi", "tur" to "Turkish", "pol" to "Polish",
            "nld" to "Dutch", "swe" to "Swedish", "nor" to "Norwegian",
            "dan" to "Danish", "fin" to "Finnish", "ces" to "Czech",
            "hun" to "Hungarian", "ron" to "Romanian", "ell" to "Greek",
            "heb" to "Hebrew", "tha" to "Thai", "vie" to "Vietnamese",
            "ind" to "Indonesian", "msa" to "Malay", "fil" to "Filipino",
            "ukr" to "Ukrainian", "bul" to "Bulgarian", "hrv" to "Croatian",
            "srp" to "Serbian", "slk" to "Slovak", "slv" to "Slovenian",
            "est" to "Estonian", "lav" to "Latvian", "lit" to "Lithuanian",
            // ISO 639-1 codes (2-letter)
            "en" to "English", "es" to "Spanish", "pt" to "Portuguese",
            "fr" to "French", "de" to "German", "it" to "Italian",
            "ru" to "Russian", "ja" to "Japanese", "ko" to "Korean",
            "zh" to "Chinese", "ar" to "Arabic", "hi" to "Hindi",
            "tr" to "Turkish", "pl" to "Polish", "nl" to "Dutch",
            "sv" to "Swedish", "no" to "Norwegian", "da" to "Danish",
            "fi" to "Finnish", "cs" to "Czech", "hu" to "Hungarian",
            "ro" to "Romanian", "el" to "Greek", "he" to "Hebrew",
            "th" to "Thai", "vi" to "Vietnamese", "id" to "Indonesian",
            "ms" to "Malay", "uk" to "Ukrainian", "bg" to "Bulgarian",
            "hr" to "Croatian", "sr" to "Serbian", "sk" to "Slovak",
            "sl" to "Slovenian", "et" to "Estonian", "lv" to "Latvian",
            "lt" to "Lithuanian"
        )

        fun formatLanguageCode(code: String): String {
            return languageNames[code.lowercase()] ?: code.uppercase()
        }

        fun fromJson(json: JSONObject, source: String): StremioSubtitle {
            val url = json.optString("url", "")
            val lang = json.optString("lang", "unknown")
            val id = json.optString("id")
                .takeIf { it.isNotEmpty() }
                ?: "${source}_${lang}_${url.hashCode()}"

            return StremioSubtitle(
                id = id,
                url = url,
                lang = lang,
                label = json.optString("label").takeIf { it.isNotEmpty() },
                source = source
            )
        }
    }
}

/**
 * Represents a Stremio addon configuration stored in SharedPreferences.
 */
data class StremioAddon(
    val id: String,
    val name: String,
    val baseUrl: String,
    val resources: List<String>,
    val types: List<String>,
    val enabled: Boolean
) {
    val supportsSubtitles: Boolean
        get() = resources.contains("subtitles")

    val supportsMovies: Boolean
        get() = types.contains("movie")

    val supportsSeries: Boolean
        get() = types.contains("series")

    companion object {
        fun fromJson(json: JSONObject): StremioAddon {
            val resources = mutableListOf<String>()
            json.optJSONArray("resources")?.let { arr ->
                for (i in 0 until arr.length()) {
                    resources.add(arr.getString(i))
                }
            }

            val types = mutableListOf<String>()
            json.optJSONArray("types")?.let { arr ->
                for (i in 0 until arr.length()) {
                    types.add(arr.getString(i))
                }
            }

            return StremioAddon(
                id = json.optString("id", "unknown"),
                name = json.optString("name", "Unknown Addon"),
                baseUrl = json.optString("base_url", ""),
                resources = resources,
                types = types,
                enabled = json.optBoolean("enabled", true)
            )
        }
    }
}

/**
 * Service for fetching subtitles from Stremio addons on Android TV.
 *
 * Mirrors the Flutter StremioSubtitleService:
 * - Loads addon configs from SharedPreferences (flutter.stremio_addons_v1)
 * - Fetches subtitles in parallel from enabled subtitle addons
 * - Deduplicates results by URL
 */
class StremioSubtitleService(private val context: Context) {

    companion object {
        private const val TAG = "StremioSubtitleService"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val ADDONS_KEY = "flutter.stremio_addons_v1"
        private const val REQUEST_TIMEOUT_MS = 30000
    }

    /**
     * Get all enabled subtitle addons from SharedPreferences.
     */
    fun getSubtitleAddons(): List<StremioAddon> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val addonsJson = prefs.getString(ADDONS_KEY, null)

        if (addonsJson.isNullOrEmpty()) {
            return emptyList()
        }

        return try {
            val addonsArray = JSONArray(addonsJson)
            val allAddons = mutableListOf<StremioAddon>()

            for (i in 0 until addonsArray.length()) {
                val addonJson = addonsArray.getJSONObject(i)
                allAddons.add(StremioAddon.fromJson(addonJson))
            }

            allAddons.filter { it.enabled && it.supportsSubtitles }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse addons", e)
            emptyList()
        }
    }

    /**
     * Fetch subtitles for content from all enabled subtitle addons.
     *
     * @param type Content type ('movie' or 'series')
     * @param imdbId IMDB ID (e.g., 'tt1234567')
     * @param season Season number for series (optional)
     * @param episode Episode number for series (optional)
     * @return List of unique subtitles from all addons
     */
    suspend fun fetchSubtitles(
        type: String,
        imdbId: String,
        season: Int? = null,
        episode: Int? = null
    ): List<StremioSubtitle> = withContext(Dispatchers.IO) {
        val addons = getSubtitleAddons()

        if (addons.isEmpty()) {
            return@withContext emptyList()
        }

        // Filter addons that support the content type
        val applicableAddons = addons.filter { addon ->
            when (type) {
                "movie" -> addon.supportsMovies
                "series" -> addon.supportsSeries
                else -> addon.types.contains(type) || addon.types.isEmpty()
            }
        }

        if (applicableAddons.isEmpty()) {
            return@withContext emptyList()
        }

        // Build subtitle ID (only add season:episode for series)
        val subtitleId = buildSubtitleId(imdbId, season, episode)

        // Fetch from all applicable addons in parallel
        val results = applicableAddons.map { addon ->
            async {
                try {
                    fetchSubtitlesFromAddon(addon, type, subtitleId)
                } catch (e: Exception) {
                    Log.e(TAG, "${addon.name} error: ${e.message}")
                    emptyList()
                }
            }
        }.awaitAll()

        // Flatten and deduplicate by URL
        val seenUrls = mutableSetOf<String>()
        val allSubtitles = mutableListOf<StremioSubtitle>()

        for (subtitleList in results) {
            for (subtitle in subtitleList) {
                if (subtitle.url.isNotEmpty() && !seenUrls.contains(subtitle.url)) {
                    seenUrls.add(subtitle.url)
                    allSubtitles.add(subtitle)
                }
            }
        }

        // Sort by display name
        allSubtitles.sortBy { it.displayName }
        allSubtitles
    }

    /**
     * Blocking version of fetchSubtitles for Java interop.
     * This can be called from a background thread in Java code.
     */
    @JvmOverloads
    fun fetchSubtitlesBlocking(
        type: String,
        imdbId: String,
        season: Int? = null,
        episode: Int? = null
    ): List<StremioSubtitle> {
        return kotlinx.coroutines.runBlocking {
            fetchSubtitles(type, imdbId, season, episode)
        }
    }

    /**
     * Build the subtitle ID for API request.
     * For series: tt1234567:season:episode
     * For movies: tt1234567 (no season/episode suffix)
     */
    private fun buildSubtitleId(imdbId: String, season: Int?, episode: Int?): String {
        return if (season != null && episode != null && (season > 0 || episode > 0)) {
            "$imdbId:$season:$episode"
        } else {
            imdbId
        }
    }

    /**
     * Fetch subtitles from a single addon.
     */
    private fun fetchSubtitlesFromAddon(
        addon: StremioAddon,
        type: String,
        subtitleId: String
    ): List<StremioSubtitle> {
        val url = "${addon.baseUrl}/subtitles/$type/$subtitleId.json"

        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = REQUEST_TIMEOUT_MS
        connection.readTimeout = REQUEST_TIMEOUT_MS
        connection.requestMethod = "GET"
        connection.setRequestProperty("User-Agent", "Debrify/1.0")

        try {
            val responseCode = connection.responseCode
            if (responseCode != 200) {
                throw Exception("HTTP $responseCode")
            }

            val response = connection.inputStream.bufferedReader().use { it.readText() }
            val data = JSONObject(response)
            val subtitlesArray = data.optJSONArray("subtitles")

            if (subtitlesArray == null || subtitlesArray.length() == 0) {
                return emptyList()
            }

            val subtitles = mutableListOf<StremioSubtitle>()
            for (i in 0 until subtitlesArray.length()) {
                val subtitleJson = subtitlesArray.getJSONObject(i)
                val subtitle = StremioSubtitle.fromJson(subtitleJson, addon.name)
                if (subtitle.url.isNotEmpty()) {
                    subtitles.add(subtitle)
                }
            }

            return subtitles
        } finally {
            connection.disconnect()
        }
    }
}
