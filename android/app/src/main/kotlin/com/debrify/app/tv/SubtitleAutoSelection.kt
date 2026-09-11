package com.debrify.app.tv

import androidx.media3.common.Format
import androidx.media3.common.MimeTypes

/** Readiness belongs to one media source, independently of manual subtitle choices. */
internal class SubtitleTrackReadiness {
    private var discovered = false

    fun onMediaReplacement() { discovered = false }
    fun onReady() { discovered = true }
    fun canSelect(playerReady: Boolean): Boolean = discovered && playerReady
}

/** Media3's default HLS extractor invents an undeclared, untagged CEA-608
 * track with no accessibility channel. Declared captions carry a channel. */
internal fun isUndeclaredHlsCaption(
    isHls: Boolean,
    mimeType: String?,
    accessibilityChannel: Int,
    language: String?,
): Boolean = isHls && mimeType == MimeTypes.APPLICATION_CEA608 &&
    accessibilityChannel == Format.NO_VALUE &&
    (language.isNullOrBlank() || language == "und")

internal data class EmbeddedSubtitleCandidate(
    val supported: Boolean,
    val selected: Boolean,
    val matchesLanguage: Boolean,
    val defaultTrack: Boolean,
    val undeclaredHlsCaption: Boolean = false,
)

internal sealed class SubtitleAutoSelection {
    object Wait : SubtitleAutoSelection()
    object Keep : SubtitleAutoSelection()
    object Addon : SubtitleAutoSelection()
    data class AddonTrack(val addonId: String, val index: Int) : SubtitleAutoSelection()
    data class Embedded(val index: Int) : SubtitleAutoSelection()
}

internal data class AddonSubtitleCandidate(
    val addonId: String,
    val loading: Boolean,
    val matchingIndices: List<Int>,
)

/** Decide only after the current media's tracks are ready, regardless of addon timing. */
internal fun chooseAutomaticSubtitle(
    tracksReady: Boolean,
    preference: String?,
    manualSelection: Boolean,
    suppressed: Boolean,
    addonSelected: Boolean,
    candidates: List<EmbeddedSubtitleCandidate>,
    sourcePriority: List<String> = listOf("embedded"),
    addons: List<AddonSubtitleCandidate> = emptyList(),
    addonDiscoveryReady: Boolean = true,
): SubtitleAutoSelection {
    if (manualSelection || suppressed || preference == "off" || addonSelected) {
        return SubtitleAutoSelection.Keep
    }
    if (!tracksReady) return SubtitleAutoSelection.Wait
    val eligible = candidates.indices.filter {
        candidates[it].supported && !candidates[it].undeclaredHlsCaption &&
            (preference == null || candidates[it].matchesLanguage)
    }
    val best = eligible.firstOrNull { candidates[it].selected }
        ?: eligible.firstOrNull { candidates[it].matchesLanguage }
        ?: eligible.firstOrNull { candidates[it].defaultTrack }
        ?: eligible.firstOrNull()
    val saved = (sourcePriority + "embedded").distinct()
    // Before discovery, a preferred addon may still be unknown. Do not let
    // embedded win early just because video metadata arrived first.
    if (!addonDiscoveryReady && (best == null || saved.first() != "embedded")) {
        return SubtitleAutoSelection.Wait
    }
    val available = listOf("embedded") + addons.map { "addon:${it.addonId}" }
    val order = (saved.filter { it in available } + available).distinct()
    for (source in order) {
        if (source == "embedded") {
            if (best != null) return SubtitleAutoSelection.Embedded(best)
        } else {
            val slot = addons.firstOrNull { "addon:${it.addonId}" == source } ?: continue
            if (slot.loading) return SubtitleAutoSelection.Wait
            slot.matchingIndices.firstOrNull()?.let {
                return SubtitleAutoSelection.AddonTrack(slot.addonId, it)
            }
        }
    }
    return SubtitleAutoSelection.Addon
}
