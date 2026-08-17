package com.debrify.app.subtitle

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
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
    val source: String,
    val addonId: String = ""   // stable StremioAddon.id — for per-addon grouping/retry
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
            "fas" to "Persian", "tel" to "Telugu", "tam" to "Tamil",
            "mal" to "Malayalam", "kan" to "Kannada", "mar" to "Marathi",
            "guj" to "Gujarati", "pan" to "Punjabi", "ben" to "Bengali",
            "urd" to "Urdu", "sin" to "Sinhalese", "cat" to "Catalan",
            "glg" to "Galician", "eus" to "Basque", "isl" to "Icelandic",
            "mkd" to "Macedonian", "bos" to "Bosnian", "sqi" to "Albanian",
            "hye" to "Armenian", "kat" to "Georgian", "aze" to "Azerbaijani",
            "kaz" to "Kazakh", "mya" to "Burmese", "khm" to "Khmer",
            // ISO 639-2/B variants (OpenSubtitles mixes B and T codes, e.g. "fre")
            "fre" to "French", "ger" to "German", "dut" to "Dutch",
            "gre" to "Greek", "cze" to "Czech", "rum" to "Romanian",
            "per" to "Persian", "slo" to "Slovak", "may" to "Malay",
            "ice" to "Icelandic", "alb" to "Albanian", "arm" to "Armenian",
            "baq" to "Basque", "geo" to "Georgian", "mac" to "Macedonian",
            "bur" to "Burmese", "wel" to "Welsh",
            // OpenSubtitles-specific codes
            "pob" to "Portuguese (BR)", "pb" to "Portuguese (BR)",
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
            "lt" to "Lithuanian", "fa" to "Persian", "te" to "Telugu",
            "ta" to "Tamil", "ml" to "Malayalam", "kn" to "Kannada",
            "mr" to "Marathi", "gu" to "Gujarati", "pa" to "Punjabi",
            "bn" to "Bengali", "ur" to "Urdu", "si" to "Sinhalese",
            "ca" to "Catalan", "gl" to "Galician", "eu" to "Basque",
            "is" to "Icelandic", "mk" to "Macedonian", "bs" to "Bosnian",
            "sq" to "Albanian", "hy" to "Armenian", "ka" to "Georgian",
            "az" to "Azerbaijani", "kk" to "Kazakh", "my" to "Burmese",
            "km" to "Khmer"
        )

        fun formatLanguageCode(code: String): String {
            return languageNames[code.lowercase()] ?: code.uppercase()
        }

        fun fromJson(json: JSONObject, source: String, addonId: String = ""): StremioSubtitle {
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
                source = source,
                addonId = addonId
            )
        }
    }
}

/** Per-addon subtitle fetch status, for the unified menu's per-addon rows. */
enum class AddonSubtitleStatus { LOADING, OK, FAILED }

/** Result of fetching subtitles from a single addon (kept per-addon for retry). */
data class AddonSubtitleResult(
    val addon: StremioAddon,
    val status: AddonSubtitleStatus,
    val subtitles: List<StremioSubtitle> = emptyList(),
    val error: String? = null
)

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
        private const val REQUEST_TIMEOUT_MS = 15000
        private const val MAX_ATTEMPTS = 3
        private const val INITIAL_BACKOFF_MS = 500L
        private const val BACKOFF_MULTIPLIER = 3
    }

    /**
     * Get all enabled subtitle addons from SharedPreferences.
     */
    fun getSubtitleAddons(): List<StremioAddon> {
        val addonsJson = com.debrify.app.profiles.ProfilePreferenceProjection.getString(
            context,
            "stremio_addons_v1",
            null,
        )

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

        // Build subtitle ID (only add season:episode for series)
        val subtitleId = buildSubtitleId(imdbId, season, episode)

        // Fetch from every subtitle addon in parallel. We intentionally don't
        // filter by the addon's declared `types` — that field describes an
        // addon's catalogs/metas, not its subtitle endpoint, and many addons
        // misconfigure it. If an addon has the `subtitles` resource, we ask it.
        val results = addons.map { addon ->
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
     * Fetch subtitles from a SINGLE addon. Unlike [fetchSubtitles] this does not
     * swallow errors — [fetchSubtitlesFromAddon] rethrows once its retry ladder is
     * exhausted, so the caller can surface a FAILED state and offer a per-addon retry.
     */
    suspend fun fetchSubtitlesForAddon(
        addon: StremioAddon,
        type: String,
        imdbId: String,
        season: Int? = null,
        episode: Int? = null
    ): List<StremioSubtitle> = withContext(Dispatchers.IO) {
        val subtitleId = buildSubtitleId(imdbId, season, episode)
        fetchSubtitlesFromAddon(addon, type, subtitleId)
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
     * Fetch subtitles from a single addon, retrying on any failure.
     *
     * Stremio addon quality varies — some return incorrect status codes,
     * intermittently time out, or briefly 5xx. We retry any thrown exception
     * (HTTP non-200, timeout, socket error, JSON parse error) up to
     * MAX_ATTEMPTS times with exponential backoff. A valid JSON response
     * with no subtitles is NOT treated as failure — it just means the addon
     * has nothing for this content.
     */
    private suspend fun fetchSubtitlesFromAddon(
        addon: StremioAddon,
        type: String,
        subtitleId: String
    ): List<StremioSubtitle> {
        val url = "${addon.baseUrl}/subtitles/$type/$subtitleId.json"

        var lastError: Exception? = null
        var backoffMs = INITIAL_BACKOFF_MS

        for (attempt in 1..MAX_ATTEMPTS) {
            try {
                return attemptFetch(addon, url)
            } catch (e: Exception) {
                lastError = e
                Log.w(TAG, "${addon.name} attempt $attempt/$MAX_ATTEMPTS failed: ${e.message}")
                if (attempt < MAX_ATTEMPTS) {
                    delay(backoffMs)
                    backoffMs *= BACKOFF_MULTIPLIER
                }
            }
        }

        Log.e(TAG, "${addon.name} exhausted $MAX_ATTEMPTS attempts, giving up")
        throw lastError ?: Exception("All retry attempts failed")
    }

    /**
     * Single fetch attempt. Throws on HTTP non-200, timeout, socket error,
     * or JSON parse failure. Returns an empty list if the addon responds
     * successfully with no subtitles.
     */
    private fun attemptFetch(
        addon: StremioAddon,
        url: String
    ): List<StremioSubtitle> {
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
                val subtitle = StremioSubtitle.fromJson(subtitleJson, addon.name, addon.id)
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
