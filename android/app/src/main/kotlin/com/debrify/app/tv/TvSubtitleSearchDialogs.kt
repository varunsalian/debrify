package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.text.InputType
import android.util.Log
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import androidx.core.content.ContextCompat
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.AppCompatButton
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import com.debrify.app.MainActivity
import com.debrify.app.R
import com.debrify.app.subtitle.StremioSubtitleService
import com.debrify.app.util.OffsetRenderersFactory
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope

internal class TvSubtitleSearchDialogs(
    private val activity: AppCompatActivity,
    private val host: TvSubtitleSourcesController.Host,
    private val sources: TvSubtitleSourcesController,
) {

    fun showSearchSubtitleDialog() {
        val currentItem = getCurrentSubtitleSearchItem()
        if (currentItem == null) {
            Toast.makeText(activity, "No current video to search", Toast.LENGTH_SHORT).show()
            return
        }

        val results = mutableListOf<SubtitleCatalogResult>()
        val adapter = createSubtitleCatalogResultAdapter(results)

        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(host.dp(24), host.dp(8), host.dp(24), 0)
        }

        val queryInput = EditText(activity).apply {
            setSingleLine(true)
            hint = "Movie or show title"
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_SEARCH
            setText(buildSubtitleSearchInitialQuery(currentItem))
            setSelectAllOnFocus(true)
            setTextColor(Color.WHITE)
            setHintTextColor(0x80FFFFFF.toInt())
        }

        val actionRow = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, host.dp(12), 0, host.dp(8))
        }

        val searchButton = AppCompatButton(activity).apply {
            text = "Search"
            isFocusable = true
            isAllCaps = true
            setTextColor(Color.WHITE)
            setBackgroundResource(R.drawable.subtitle_search_button_bg)
            stateListAnimator = null
            minimumHeight = host.dp(44)
        }

        val progressBar = ProgressBar(activity).apply {
            isIndeterminate = true
            visibility = View.GONE
        }

        actionRow.addView(
            searchButton,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        )
        actionRow.addView(
            progressBar,
            LinearLayout.LayoutParams(host.dp(48), host.dp(48)).apply {
                leftMargin = host.dp(16)
            }
        )

        val statusText = TextView(activity).apply {
            text = "Find subtitles by choosing the correct title."
            setPadding(0, 0, 0, host.dp(8))
            setTextColor(0xB3FFFFFF.toInt())
        }

        val resultList = ListView(activity).apply {
            this.adapter = adapter
            isFocusable = true
            isFocusableInTouchMode = true
            selector = ContextCompat.getDrawable(context, R.drawable.subtitle_catalog_row_selector)
            isDrawSelectorOnTop = false
            divider = ColorDrawable(0x14FFFFFF)
            dividerHeight = 1
            // Keep the DPAD-focused row fully on screen: with bottom padding + clipToPadding
            // off, ListView scrolls the selection above the padding instead of half-clipping it.
            clipToPadding = false
            setPadding(0, 0, 0, host.dp(48))
            emptyView = null
        }

        container.addView(
            queryInput,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        container.addView(
            actionRow,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        container.addView(
            statusText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        container.addView(
            resultList,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                host.dp(360)
            )
        )

        lateinit var dialog: AlertDialog

        fun setLoading(loading: Boolean) {
            progressBar.visibility = if (loading) View.VISIBLE else View.GONE
            searchButton.isEnabled = !loading
            queryInput.isEnabled = !loading
            if (loading) {
                statusText.text = "Searching..."
            }
        }

        fun updateResults(newResults: List<SubtitleCatalogResult>) {
            results.clear()
            results.addAll(newResults)
            adapter.notifyDataSetChanged()
            statusText.text = when {
                newResults.isEmpty() -> "No matching movie/show results found."
                newResults.size == 1 -> "1 result"
                else -> "${newResults.size} results"
            }
            if (newResults.isNotEmpty()) {
                resultList.requestFocus()
                resultList.setSelection(0)
            } else {
                searchButton.requestFocus()
            }
        }

        fun performSearch() {
            val query = queryInput.text?.toString()?.trim().orEmpty()
            if (query.isEmpty()) {
                results.clear()
                adapter.notifyDataSetChanged()
                statusText.text = "Enter a title to search."
                queryInput.requestFocus()
                return
            }

            setLoading(true)
            requestSubtitleCatalogSearchFromFlutter(
                query,
                onSuccess = { searchResults ->
                    if (!dialog.isShowing) return@requestSubtitleCatalogSearchFromFlutter
                    setLoading(false)
                    updateResults(searchResults)
                },
                onError = { message ->
                    if (!dialog.isShowing) return@requestSubtitleCatalogSearchFromFlutter
                    setLoading(false)
                    results.clear()
                    adapter.notifyDataSetChanged()
                    statusText.text = message
                    searchButton.requestFocus()
                }
            )
        }

        resultList.setOnItemClickListener { _, _, position, _ ->
            val selected = adapter.getItem(position) ?: return@setOnItemClickListener
            val item = getCurrentSubtitleSearchItem()
            if (item == null) {
                Toast.makeText(activity, "No current video to search", Toast.LENGTH_SHORT).show()
                return@setOnItemClickListener
            }

            dialog.dismiss()
            if (selected.type == "series") {
                val resolvedEpisode = resolveSeasonEpisodeForSubtitle(item)
                if (resolvedEpisode != null) {
                    sources.applyManualSubtitleIdentity(
                        selected,
                        resolvedEpisode.season,
                        resolvedEpisode.episode
                    )
                } else {
                    showSeasonEpisodePrompt(selected)
                }
            } else {
                sources.applyManualSubtitleIdentity(selected, null, null)
            }
        }

        searchButton.setOnClickListener { performSearch() }
        queryInput.setOnEditorActionListener { _, actionId, event ->
            val isSearchAction = actionId == EditorInfo.IME_ACTION_SEARCH
            val isEnterKey = event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_UP
            if (isSearchAction || isEnterKey) {
                performSearch()
                true
            } else {
                false
            }
        }

        dialog = AlertDialog.Builder(activity, R.style.Theme_Debrify_SubtitleDialog)
            .setTitle("Search Movie/Show Subtitles")
            .setView(container)
            .setNegativeButton("Cancel", null)
            .create()

        dialog.setOnShowListener {
            searchButton.requestFocus()
        }
        dialog.show()
    }

    fun getCurrentSubtitleSearchItem(): PlaybackItem? {
        host.payload?.items?.getOrNull(host.currentIndex)?.let { return it }

        if (host.isIptvMode && host.currentIptvIndex in host.iptvChannels.indices) {
            val entry = host.iptvChannels[host.currentIptvIndex]
            return PlaybackItem(
                id = "iptv:${entry.index}",
                title = entry.name,
                url = entry.url,
                hdVideoUrl = null,
                audioUrl = null,
                index = 0,
                season = null,
                episode = null,
                artwork = entry.logoUrl,
                description = entry.group,
                resumePositionMs = 0L,
                durationMs = 0L,
                updatedAt = System.currentTimeMillis(),
                resumeId = null,
                sizeBytes = null,
                rating = null,
                provider = "iptv",
            )
        }

        val mediaItem = host.player?.currentMediaItem ?: return null
        val mediaTitle = mediaItem.mediaMetadata.title?.toString()?.trim()
        val mediaUrl = mediaItem.localConfiguration?.uri?.toString().orEmpty()
        val fallbackTitle = mediaTitle
            ?.takeIf { it.isNotEmpty() }
            ?: mediaUrl.substringAfterLast('/').substringBefore('?').takeIf { it.isNotEmpty() }
            ?: return null

        return PlaybackItem(
            id = "current:${fallbackTitle.hashCode()}",
            title = fallbackTitle,
            url = mediaUrl,
            hdVideoUrl = null,
            audioUrl = null,
            index = host.currentIndex,
            season = null,
            episode = null,
            artwork = null,
            description = null,
            resumePositionMs = 0L,
            durationMs = 0L,
            updatedAt = System.currentTimeMillis(),
            resumeId = null,
            sizeBytes = null,
            rating = null,
            provider = null,
        )
    }

    fun requestSubtitleCatalogSearchFromFlutter(
        query: String,
        onSuccess: (List<SubtitleCatalogResult>) -> Unit,
        onError: (String) -> Unit
    ) {
        try {
            val channel = MainActivity.getAndroidTvPlayerChannel()
            if (channel == null) {
                onError("Subtitle search is unavailable.")
                return
            }

            channel.invokeMethod(
                "searchSubtitleCatalogs",
                hashMapOf<String, Any?>("query" to query),
                object : io.flutter.plugin.common.MethodChannel.Result {
                    override fun success(result: Any?) {
                        val parsedResults = parseSubtitleCatalogResults(result)
                        activity.runOnUiThread { onSuccess(parsedResults) }
                    }

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        android.util.Log.e("StremioSubs", "Subtitle catalog search failed: $errorCode - $errorMessage")
                        activity.runOnUiThread {
                            onError(errorMessage ?: "Subtitle search failed.")
                        }
                    }

                    override fun notImplemented() {
                        android.util.Log.e("StremioSubs", "Subtitle catalog search is not implemented")
                        activity.runOnUiThread { onError("Subtitle search is unavailable.") }
                    }
                }
            )
        } catch (e: Exception) {
            android.util.Log.e("StremioSubs", "Subtitle catalog search exception", e)
            onError("Subtitle search failed.")
        }
    }

    private fun createSubtitleCatalogResultAdapter(
        results: MutableList<SubtitleCatalogResult>
    ): ArrayAdapter<SubtitleCatalogResult> {
        return object : ArrayAdapter<SubtitleCatalogResult>(activity, 0, results) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                val row = (convertView as? LinearLayout) ?: LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    setPadding(host.dp(20), host.dp(12), host.dp(20), host.dp(12))
                    minimumHeight = host.dp(72)
                }
                row.removeAllViews()

                val item = getItem(position)
                val title = TextView(context).apply {
                    text = item?.titleLine().orEmpty()
                    textSize = 18f
                    setTextColor(Color.WHITE)
                    typeface = Typeface.DEFAULT_BOLD
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }
                val detail = TextView(context).apply {
                    text = item?.detailLine().orEmpty()
                    textSize = 14f
                    setTextColor(Color.LTGRAY)
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }

                row.addView(
                    title,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                )
                row.addView(
                    detail,
                    LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                )
                return row
            }
        }
    }

    fun showSeasonEpisodePrompt(result: SubtitleCatalogResult) {
        val currentItem = getCurrentSubtitleSearchItem()

        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(host.dp(24), host.dp(8), host.dp(24), 0)
        }

        val title = TextView(activity).apply {
            text = result.titleLine()
            textSize = 18f
            setPadding(0, 0, 0, host.dp(12))
        }

        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
        }

        val seasonInput = EditText(activity).apply {
            hint = "Season"
            inputType = InputType.TYPE_CLASS_NUMBER
            imeOptions = EditorInfo.IME_ACTION_NEXT
            setText((currentItem?.season ?: sources.manualSubtitleSeason ?: 1).toString())
            setSelectAllOnFocus(true)
            setTextColor(Color.WHITE)
            setHintTextColor(0x80FFFFFF.toInt())
        }

        val episodeInput = EditText(activity).apply {
            hint = "Episode"
            inputType = InputType.TYPE_CLASS_NUMBER
            imeOptions = EditorInfo.IME_ACTION_DONE
            setText((currentItem?.episode ?: sources.manualSubtitleEpisode ?: 1).toString())
            setSelectAllOnFocus(true)
            setTextColor(Color.WHITE)
            setHintTextColor(0x80FFFFFF.toInt())
        }

        row.addView(
            seasonInput,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                rightMargin = host.dp(12)
            }
        )
        row.addView(
            episodeInput,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        )
        container.addView(
            title,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )
        container.addView(
            row,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        )

        val dialog = AlertDialog.Builder(activity, R.style.Theme_Debrify_SubtitleDialog)
            .setTitle("Series Episode")
            .setView(container)
            .setPositiveButton("Search", null)
            .setNegativeButton("Cancel", null)
            .create()

        fun submit() {
            val season = seasonInput.text?.toString()?.toIntOrNull()
            val episode = episodeInput.text?.toString()?.toIntOrNull()
            if (season == null || episode == null || season <= 0 || episode <= 0) {
                Toast.makeText(activity, "Enter a valid season and episode", Toast.LENGTH_SHORT).show()
                return
            }

            dialog.dismiss()
            sources.applyManualSubtitleIdentity(result, season, episode)
        }

        episodeInput.setOnEditorActionListener { _, actionId, event ->
            val isDoneAction = actionId == EditorInfo.IME_ACTION_DONE
            val isEnterKey = event?.keyCode == KeyEvent.KEYCODE_ENTER && event.action == KeyEvent.ACTION_UP
            if (isDoneAction || isEnterKey) {
                submit()
                true
            } else {
                false
            }
        }

        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener { submit() }
            seasonInput.requestFocus()
        }
        dialog.show()
    }
}
