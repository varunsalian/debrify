package com.debrify.app.util

/**
 * Utility for robust subtitle language matching.
 * Handles ISO 639-1, ISO 639-2, regional variants, and common language names.
 */
object LanguageMapper {

    /**
     * Comprehensive language code mapping.
     * Maps ISO 639-1 (2-letter) codes to all known variants.
     */
    private val languageVariants = mapOf(
        "en" to setOf("en", "eng", "english", "en-us", "en-gb", "en-au", "en-ca", "en-nz", "en-ie", "en-za"),
        "es" to setOf("es", "spa", "spanish", "español", "espanol", "es-es", "es-mx", "es-ar", "es-co", "es-419", "es-la", "lat", "latino"),
        "fr" to setOf("fr", "fra", "fre", "french", "français", "francais", "fr-fr", "fr-ca", "fr-be", "fr-ch"),
        "de" to setOf("de", "deu", "ger", "german", "deutsch", "de-de", "de-at", "de-ch"),
        "it" to setOf("it", "ita", "italian", "italiano", "it-it", "it-ch"),
        "pt" to setOf("pt", "por", "portuguese", "português", "portugues", "pt-pt", "pt-br", "pb", "pob"),
        "ru" to setOf("ru", "rus", "russian", "русский", "russkiy", "ru-ru"),
        "ja" to setOf("ja", "jpn", "japanese", "日本語", "nihongo", "ja-jp", "jp"),
        "ko" to setOf("ko", "kor", "korean", "한국어", "hangugeo", "ko-kr", "kr"),
        "zh" to setOf("zh", "zho", "chi", "chinese", "中文", "zhongwen", "zh-cn", "zh-tw", "zh-hk", "zh-sg", "zh-hans", "zh-hant", "cmn", "yue", "mandarin", "cantonese"),
        "ar" to setOf("ar", "ara", "arabic", "العربية", "arabiya", "ar-sa", "ar-eg", "ar-ae"),
        "hi" to setOf("hi", "hin", "hindi", "हिन्दी", "हिंदी", "hi-in"),
        "nl" to setOf("nl", "nld", "dut", "dutch", "nederlands", "nl-nl", "nl-be", "flemish", "vlaams"),
        "pl" to setOf("pl", "pol", "polish", "polski", "pl-pl"),
        "tr" to setOf("tr", "tur", "turkish", "türkçe", "turkce", "tr-tr"),
        "sv" to setOf("sv", "swe", "swedish", "svenska", "sv-se"),
        "da" to setOf("da", "dan", "danish", "dansk", "da-dk"),
        "no" to setOf("no", "nor", "nob", "nno", "norwegian", "norsk", "no-no", "nb", "nn", "nb-no", "nn-no", "bokmal", "bokmål", "nynorsk"),
        "fi" to setOf("fi", "fin", "finnish", "suomi", "fi-fi"),
        "el" to setOf("el", "ell", "gre", "greek", "ελληνικά", "ellinika", "el-gr"),
        "he" to setOf("he", "heb", "hebrew", "עברית", "ivrit", "he-il", "iw"),
        "th" to setOf("th", "tha", "thai", "ไทย", "th-th"),
        "vi" to setOf("vi", "vie", "vietnamese", "tiếng việt", "tieng viet", "vi-vn"),
        "id" to setOf("id", "ind", "indonesian", "bahasa indonesia", "id-id", "in"),
        "ms" to setOf("ms", "msa", "may", "malay", "bahasa melayu", "ms-my"),
        "cs" to setOf("cs", "ces", "cze", "czech", "čeština", "cestina", "cs-cz"),
        "sk" to setOf("sk", "slk", "slo", "slovak", "slovenčina", "slovencina", "sk-sk"),
        "hu" to setOf("hu", "hun", "hungarian", "magyar", "hu-hu"),
        "ro" to setOf("ro", "ron", "rum", "romanian", "română", "romana", "ro-ro"),
        "bg" to setOf("bg", "bul", "bulgarian", "български", "balgarski", "bg-bg"),
        "uk" to setOf("uk", "ukr", "ukrainian", "українська", "ukrainska", "uk-ua"),
        "hr" to setOf("hr", "hrv", "croatian", "hrvatski", "hr-hr"),
        "sr" to setOf("sr", "srp", "serbian", "српски", "srpski", "sr-rs", "sr-latn", "sr-cyrl"),
        "sl" to setOf("sl", "slv", "slovenian", "slovenščina", "slovenscina", "sl-si"),
        "et" to setOf("et", "est", "estonian", "eesti", "et-ee"),
        "lv" to setOf("lv", "lav", "latvian", "latviešu", "latviesu", "lv-lv"),
        "lt" to setOf("lt", "lit", "lithuanian", "lietuvių", "lietuviu", "lt-lt"),
        "fa" to setOf("fa", "fas", "per", "persian", "farsi", "فارسی", "fa-ir"),
        "bn" to setOf("bn", "ben", "bengali", "bangla", "বাংলা", "bn-bd", "bn-in"),
        "ta" to setOf("ta", "tam", "tamil", "தமிழ்", "ta-in", "ta-lk"),
        "te" to setOf("te", "tel", "telugu", "తెలుగు", "te-in"),
        "mr" to setOf("mr", "mar", "marathi", "मराठी", "mr-in"),
        "gu" to setOf("gu", "guj", "gujarati", "ગુજરાતી", "gu-in"),
        "kn" to setOf("kn", "kan", "kannada", "ಕನ್ನಡ", "kn-in"),
        "ml" to setOf("ml", "mal", "malayalam", "മലയാളം", "ml-in"),
        "pa" to setOf("pa", "pan", "punjabi", "ਪੰਜਾਬੀ", "پنجابی", "pa-in", "pa-pk")
    )

    /** Reverse lookup map (built lazily). */
    private val reverseLookup: Map<String, String> by lazy {
        buildMap {
            for ((iso6391, variants) in languageVariants) {
                for (variant in variants) {
                    put(variant.lowercase(), iso6391)
                }
            }
        }
    }

    /**
     * Check if a track's language matches the target language.
     *
     * @param targetLang The user's selected language (ISO 639-1, e.g., "en")
     * @param trackLang The track's language tag (could be anything)
     * @return true if they match
     */
    @JvmStatic
    fun matchesLanguage(targetLang: String, trackLang: String?): Boolean {
        if (trackLang.isNullOrBlank()) return false

        val targetLower = targetLang.lowercase().trim()
        val trackLower = trackLang.lowercase().trim()

        // Direct match
        if (targetLower == trackLower) return true

        // Get the canonical ISO 639-1 code for target
        val targetCanonical = reverseLookup[targetLower] ?: targetLower

        // Get the variants for the target language
        val targetVariants = languageVariants[targetCanonical]
        if (targetVariants == null) {
            // Unknown language - fall back to prefix matching
            return prefixMatch(targetLower, trackLower)
        }

        // Check if track language is in the target's variants
        if (trackLower in targetVariants) return true

        // Try to normalize track language and check again
        val trackNormalized = normalizeLanguageTag(trackLower)
        if (trackNormalized in targetVariants) return true

        // Check if track's canonical form matches target
        val trackCanonical = reverseLookup[trackLower] ?: reverseLookup[trackNormalized]
        if (trackCanonical == targetCanonical) return true

        // Last resort: prefix matching for regional variants
        return prefixMatch(targetCanonical, trackLower) ||
               prefixMatch(targetCanonical, trackNormalized)
    }

    /**
     * Normalize a language tag by removing common suffixes and extracting base.
     */
    private fun normalizeLanguageTag(tag: String): String {
        // Remove common suffixes like -sdh, -forced, -cc, -full, etc.
        var normalized = tag
            .replace(Regex("[-_](sdh|forced|cc|full|commentary|descriptive|ad|hi)$", RegexOption.IGNORE_CASE), "")
            .replace(Regex("[-_](sub|subs|subtitle|subtitles)$", RegexOption.IGNORE_CASE), "")

        // Extract base language from regional variants (e.g., "en-us" -> "en")
        if ("-" in normalized || "_" in normalized) {
            val parts = normalized.split(Regex("[-_]"))
            if (parts.isNotEmpty() && parts[0].length >= 2) {
                // Check if first part is a known language code
                if (parts[0] in reverseLookup || parts[0] in languageVariants) {
                    return parts[0]
                }
            }
        }

        return normalized
    }

    /**
     * Check if track language starts with target language code.
     */
    private fun prefixMatch(target: String, track: String): Boolean {
        return track.startsWith("$target-") || track.startsWith("${target}_")
    }

    /**
     * Get all variants for a language code that ExoPlayer should try.
     * Returns a list of codes to try in order of preference.
     */
    @JvmStatic
    fun getLanguageVariantsForExoPlayer(langCode: String): List<String> {
        val canonical = reverseLookup[langCode.lowercase()] ?: langCode.lowercase()
        val variants = languageVariants[canonical] ?: return listOf(langCode)

        // Return common codes first (2-letter, then 3-letter, then others)
        return variants.sortedBy { variant ->
            when {
                variant.length == 2 -> 0
                variant.length == 3 && variant.all { it.isLetter() } -> 1
                else -> 2
            }
        }
    }
}
