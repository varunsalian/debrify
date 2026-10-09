package com.debrify.app.tv

import android.graphics.Typeface
import android.text.Spannable
import android.text.SpannableString
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.View
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import java.util.Locale

internal class TvDockIdentityPresenter(
    private val host: TvControlsOverlayController.Host,
) {
    internal var ottIdentityTitle: TextView? = null
    internal var ottIdentitySubtitle: TextView? = null

    // Optional per-skin identity views (null where a layout doesn't have them):
    // MARQUEE/TICKET show-name overline, TICKET gold S·E badge + its rule.
    internal var ottIdentityOverline: TextView? = null
    internal var ottIdentityBadge: TextView? = null
    internal var ottIdentityDivider: View? = null

    // Release-quality chips + rating (updateOttExtras): chips row on
    // FROST/BROADCAST/PULSE, serif print line on MARQUEE, gold stub on
    // TICKET. All optional per layout.
    internal val ottQualityChips = arrayOfNulls<TextView>(3)
    internal var ottRatingChip: TextView? = null
    internal var ottMetaLine: TextView? = null
    private var dockTagsCacheKey: String? = null
    private var dockTagsCache: List<DockFormatTags.Tag> = emptyList()

    /** TVMaze's official show title, pushed with the metadata updates. */
    @Volatile
    internal var ottShowName: String? = null

    private fun guideTitleFor(item: PlaybackItem): String? {
        if (item.season == null || item.episode == null) return null
        return host.payload?.guideEpisodes?.firstOrNull {
            it.season == item.season && it.episode == item.episode
        }?.title?.takeIf { it.isNotBlank() }
    }

    fun updateTitle(item: PlaybackItem) {
        // Prefer the episode label / show title when the item title is blank, so
        // a series episode never renders as just the red badge with no text (the
        // "red line" bug). If everything is blank (rare non-series case) the
        // showControlsMenu guard keeps the header hidden rather than showing empty.
        val model = host.payload
        val fallbackTitle = item.seasonEpisodeLabel().ifEmpty { model?.title.orEmpty() }
        val displayTitle = guideTitleFor(item) ?: item.title
        host.titleView.text = displayTitle.ifBlank { fallbackTitle }

        // Pre-populate OTT fields for when controls menu is shown
        if (model?.contentType?.lowercase(java.util.Locale.US) == "series") {
            if (item.season != null && item.episode != null) {
                val seasonStr = item.season.toString().padStart(2, '0')
                val episodeStr = item.episode.toString().padStart(2, '0')
                host.ottEpisodeBadge.text = "S$seasonStr E$episodeStr"
                host.ottEpisodeBadge.visibility = View.VISIBLE
            } else {
                host.ottEpisodeBadge.visibility = View.GONE
            }
            // Fall back to "Episode N" so the badge never sits next to a blank line.
            host.ottEpisodeTitle.text = displayTitle.ifBlank {
                item.episode?.let { "Episode $it" } ?: fallbackTitle
            }

            val rating = item.rating
            if (rating != null && rating > 0) {
                host.ottRatingContainer.visibility = View.VISIBLE
                host.ottRating.text = String.format(java.util.Locale.US, "%.1f", rating)
            } else {
                host.ottRatingContainer.visibility = View.GONE
            }
        }

        host.channelBadge.visibility = View.GONE
        if (host.ottSkinInstalled) updateOttIdentity()
    }

    /** The OTT dock's in-dock identity row, mirroring the legacy OTT title
     *  mode: for series the FETCHED episode title (updateTitle keeps
     *  item.title current from the TVMaze/metadata updates, with the same
     *  "Episode N" fallback) with the S/E badge beneath — the raw payload
     *  title is never shown, because on torrent launches it's the release
     *  filename the legacy header deliberately hid. */
    fun updateOttIdentity() {
        val title = ottIdentityTitle ?: return
        val model = host.payload
        val item = model?.items?.getOrNull(host.currentIndex)
        val isSeries = model?.contentType?.lowercase(java.util.Locale.US) == "series"
        val overline = ottIdentityOverline
        val badge = ottIdentityBadge
        if (isSeries && item != null && item.season != null && item.episode != null) {
            val episodeTitle = guideTitleFor(item)
                ?: item.title.ifBlank { "Episode ${item.episode}" }
            // The FETCHED show/episode names only (TVMaze via the metadata
            // pushes); never the payload title, which on torrent launches is
            // the release filename the legacy header deliberately hid. Each
            // skin arranges the same facts its own way.
            val show = ottShowName
            val seasonStr = item.season.toString().padStart(2, '0')
            val episodeStr = item.episode.toString().padStart(2, '0')
            when (host.controlsSkin) {
                TvControlsSkin.FROST -> {
                    // Eyebrow above a big episode title (subtitle view is the
                    // eyebrow in this layout, uppercased by XML).
                    title.text = episodeTitle
                    ottIdentitySubtitle?.text = if (show.isNullOrBlank()) {
                        "Season ${item.season} · Episode ${item.episode}"
                    } else {
                        "$show · Season ${item.season}"
                    }
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
                TvControlsSkin.MARQUEE -> {
                    // Italic show over a serif title, season/episode spelled
                    // out in words underneath.
                    title.text = episodeTitle
                    if (show.isNullOrBlank()) {
                        overline?.visibility = View.GONE
                    } else {
                        overline?.text = show
                        overline?.visibility = View.VISIBLE
                    }
                    ottIdentitySubtitle?.text =
                        "Season ${spellNumber(item.season)} · Episode ${spellNumber(item.episode)}"
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
                TvControlsSkin.BROADCAST -> {
                    // Channel-ident: show name leads in condensed caps.
                    if (show.isNullOrBlank()) {
                        title.text = episodeTitle
                        ottIdentitySubtitle?.text = "S$seasonStr · E$episodeStr"
                    } else {
                        title.text = show
                        ottIdentitySubtitle?.text = "E${item.episode} — $episodeTitle"
                    }
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
                TvControlsSkin.PULSE -> {
                    // Episode leads; the show name is accent-tinted inside
                    // the subtitle.
                    title.text = episodeTitle
                    val tail = "Season ${item.season}, Episode ${item.episode}"
                    ottIdentitySubtitle?.text = if (show.isNullOrBlank()) {
                        SpannableString(tail)
                    } else {
                        SpannableString("$show · $tail").apply {
                            setSpan(
                                ForegroundColorSpan(0xFF9BA5FB.toInt()),
                                0, show.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                            )
                            setSpan(
                                StyleSpan(Typeface.BOLD),
                                0, show.length, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                            )
                        }
                    }
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
                TvControlsSkin.TICKET -> {
                    // Gold S·E chip · rule · show overline / episode title.
                    title.text = episodeTitle
                    badge?.text = "S${item.season} · E${item.episode}"
                    badge?.visibility = View.VISIBLE
                    ottIdentityDivider?.visibility = View.VISIBLE
                    if (show.isNullOrBlank()) {
                        overline?.visibility = View.GONE
                    } else {
                        overline?.text = show
                        overline?.visibility = View.VISIBLE
                    }
                }
                else -> {
                    // OTT: "Show — Episode" with the S·E badge beneath.
                    title.text = if (show.isNullOrBlank()) {
                        episodeTitle
                    } else {
                        "$show — $episodeTitle"
                    }
                    ottIdentitySubtitle?.text = "S$seasonStr · E$episodeStr"
                    ottIdentitySubtitle?.visibility = View.VISIBLE
                }
            }
        } else {
            title.text = host.titleView.text
            ottIdentitySubtitle?.visibility = View.GONE
            overline?.visibility = View.GONE
            badge?.visibility = View.GONE
            ottIdentityDivider?.visibility = View.GONE
        }
        updateOttExtras(item)
    }

    /**
     * Quality chips + rating for the premium dock skins. Quality is parsed
     * from the item's ORIGINAL payload title (the release name — metadata
     * pushes overwrite item.title with the fetched episode name, so
     * [PlaybackItem.sourceTitle] carries the parseable one), falling back to
     * the stream URL's filename. Rating is [PlaybackItem.rating] — already
     * pushed with the TVMaze metadata — so no extra network. Runs AFTER the
     * per-skin identity arms; on TICKET it also owns the overline so the
     * quality can ride it ("FOUNDATION · 4K · DOLBY VISION").
     */
    private fun updateOttExtras(item: PlaybackItem?) {
        val hasAnyView = ottQualityChips.any { it != null } ||
            ottRatingChip != null || ottMetaLine != null
        if (!hasAnyView) return

        val tags = if (item != null) dockTagsFor(item) else emptyList()
        val rating = item?.rating?.takeIf { it > 0 }
        val ratingText = rating?.let { String.format(java.util.Locale.US, "%.1f", it) }

        ottQualityChips.forEachIndexed { i, chip ->
            if (chip == null) return@forEachIndexed
            val tag = tags.getOrNull(i)
            if (tag != null) {
                chip.text = tag.short
                chip.visibility = View.VISIBLE
            } else {
                chip.visibility = View.GONE
            }
        }

        ottRatingChip?.let { rc ->
            if (ratingText == null) {
                rc.visibility = View.GONE
            } else {
                val starColor = when (host.controlsSkin) {
                    TvControlsSkin.PULSE -> 0xFF818CF8.toInt()
                    TvControlsSkin.FROST -> 0xFFF5C518.toInt()
                    else -> null
                }
                if (starColor != null) {
                    rc.text = SpannableString("★ $ratingText").apply {
                        setSpan(
                            ForegroundColorSpan(starColor),
                            0, 1, Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                    }
                } else {
                    rc.text = "★ $ratingText"
                }
                rc.visibility = View.VISIBLE
            }
        }

        // MARQUEE: one serif print line — "4K · DOLBY VISION · ATMOS — ★ 8.6".
        // Uppercased HERE, not via android:textAllCaps — the AllCaps
        // transform re-renders the text as a plain string and drops the
        // rating's gold span.
        ottMetaLine?.let { ml ->
            val quality = tags.joinToString(" · ") {
                it.long.uppercase(java.util.Locale.US)
            }
            val text = when {
                quality.isEmpty() && ratingText == null -> null
                quality.isEmpty() -> "★ $ratingText"
                ratingText == null -> quality
                else -> "$quality — ★ $ratingText"
            }
            if (text == null) {
                ml.visibility = View.GONE
            } else {
                ml.text = if (ratingText != null) {
                    SpannableString(text).apply {
                        setSpan(
                            ForegroundColorSpan(0xFFEAC981.toInt()),
                            text.length - ratingText.length - 2, text.length,
                            Spannable.SPAN_EXCLUSIVE_EXCLUSIVE,
                        )
                    }
                } else {
                    text
                }
                ml.visibility = View.VISIBLE
            }
        }

        // TICKET: the quality rides the gold overline after the show name —
        // resolution short + HDR long only, per the mock. Movies (no show)
        // get the quality alone, so the overline earns its keep either way.
        if (host.controlsSkin == TvControlsSkin.TICKET) {
            val overline = ottIdentityOverline
            if (overline != null) {
                val parts = mutableListOf<String>()
                ottShowName?.takeIf { it.isNotBlank() }?.let { parts.add(it) }
                tags.firstOrNull()?.let { parts.add(it.short) }
                tags.getOrNull(1)?.let { parts.add(it.long) }
                if (parts.isEmpty()) {
                    overline.visibility = View.GONE
                } else {
                    overline.text = parts.joinToString(" · ")
                    overline.visibility = View.VISIBLE
                }
            }
        }
    }

    /** Tags for the current item, cached — the regexes only rerun when the
     *  underlying release name changes (zap / source switch). */
    private fun dockTagsFor(item: PlaybackItem): List<DockFormatTags.Tag> {
        val name = item.sourceTitle?.takeIf { it.isNotBlank() } ?: item.title
        val fromName = if (name == dockTagsCacheKey) {
            dockTagsCache
        } else {
            DockFormatTags.detect(name).also {
                dockTagsCacheKey = name
                dockTagsCache = it
            }
        }
        if (fromName.isNotEmpty()) return fromName
        // Fallback: the stream URL usually ends in the real filename
        // (debrid links keep it) even when the payload title was cleaned.
        val urlName = item.url.substringAfterLast('/').substringBefore('?')
        if (urlName.isBlank() || urlName == name) return fromName
        val decoded = try {
            java.net.URLDecoder.decode(urlName, "UTF-8")
        } catch (_: Exception) {
            urlName
        }
        return DockFormatTags.detect(decoded)
    }
}
