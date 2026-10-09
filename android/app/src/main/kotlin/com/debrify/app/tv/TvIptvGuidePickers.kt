package com.debrify.app.tv

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.text.InputType
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import androidx.core.widget.TextViewCompat
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.annotation.OptIn
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.media3.common.util.UnstableApi
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.debrify.app.MainActivity
import com.debrify.app.R
import io.flutter.plugin.common.MethodChannel

@OptIn(UnstableApi::class)
internal class TvIptvGuidePickers(
    private val activity: AppCompatActivity,
    private val host: TvIptvGuideChromeController.Host,
    private val chrome: TvIptvGuideChromeController,
) {

    fun showIptvCategoryPicker() {
        val allLabel = "All categories"
        val categories = host.iptvGuideController.iptvCategories.distinct()
        val categoryListHeight = minOf(
            host.dp(400),
            (activity.resources.displayMetrics.heightPixels * 0.5f).toInt(),
        )
        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(host.dp(24), host.dp(8), host.dp(24), 0)
        }
        val pickerTokens = host.guideTokens
        val searchInput = EditText(activity).apply {
            id = View.generateViewId()
            setSingleLine(true)
            hint = "Search categories"
            inputType = InputType.TYPE_CLASS_TEXT
            imeOptions = EditorInfo.IME_ACTION_DONE
            if (pickerTokens == null) {
                setTextColor(Color.WHITE)
                setHintTextColor(0x80FFFFFF.toInt())
                setBackgroundResource(R.drawable.iptv_guide_search_bg)
                setCompoundDrawablesWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0)
                compoundDrawablePadding = host.dp(10)
                compoundDrawableTintList =
                    android.content.res.ColorStateList.valueOf(0xB3FFFFFF.toInt())
            } else {
                setTextColor(pickerTokens.fg)
                setHintTextColor(pickerTokens.fgFaint)
                background = pickerTokens.searchDrawable(host.dp(10).toFloat())
                setCompoundDrawablesWithIntrinsicBounds(R.drawable.ic_search, 0, 0, 0)
                compoundDrawablePadding = host.dp(10)
                TextViewCompat.setCompoundDrawableTintList(
                    this,
                    android.content.res.ColorStateList.valueOf(pickerTokens.fgFaint),
                )
            }
            setPadding(host.dp(16), 0, host.dp(16), 0)
        }
        val statusText = TextView(activity).apply {
            setPadding(host.dp(2), host.dp(12), host.dp(2), host.dp(8))
            setTextColor(pickerTokens?.fgDim ?: 0xB3FFFFFF.toInt())
            textSize = 13f
        }
        val categoryList = RecyclerView(activity).apply {
            id = View.generateViewId()
            layoutManager = LinearLayoutManager(
                activity,
                LinearLayoutManager.VERTICAL,
                false,
            )
            isFocusable = true
            clipToPadding = false
            setPadding(0, 0, 0, host.dp(16))
        }

        container.addView(
            searchInput,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                host.dp(48),
            ),
        )
        container.addView(
            statusText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(
            categoryList,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                categoryListHeight,
            ),
        )

        lateinit var dialog: AlertDialog
        val adapter = IptvCategoryAdapter(
            selectedCategory = host.iptvGuideController.iptvSelectedCategory,
            searchViewId = searchInput.id,
            tokens = pickerTokens,
            rowRadiusPx = host.dp(8).toFloat(),
        ) { category ->
            dialog.dismiss()
            host.iptvGuideController.commitIptvAllCategorySearch()
            host.iptvGuideController.iptvSelectedCategory = category.takeUnless { it == allLabel }
            host.iptvGuideController.iptvGuideSearch?.setText("")
            host.iptvGuideController.refreshIptvBrowserChrome()
            host.iptvGuideController.requestIptvBrowse(action = "browse", query = "")
        }
        categoryList.adapter = adapter

        fun applyCategoryFilter(rawQuery: String) {
            val query = rawQuery.trim().lowercase()
            val terms = query.split(Regex("\\s+")).filter { it.isNotEmpty() }
            val matches = if (terms.isEmpty()) {
                categories
            } else {
                categories.filter { category ->
                    val haystack = category.lowercase()
                    terms.all(haystack::contains)
                }
            }
            adapter.update(listOf(allLabel) + matches)
            statusText.text = when {
                categories.isEmpty() -> "No categories available"
                matches.isEmpty() -> "No matching categories"
                matches.size == 1 -> "1 category"
                else -> "${matches.size} categories"
            }
        }

        searchInput.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(
                text: CharSequence?,
                start: Int,
                count: Int,
                after: Int,
            ) = Unit

            override fun onTextChanged(
                text: CharSequence?,
                start: Int,
                before: Int,
                count: Int,
            ) = Unit

            override fun afterTextChanged(text: android.text.Editable?) {
                applyCategoryFilter(text?.toString().orEmpty())
            }
        })
        searchInput.setOnKeyListener { _, keyCode, event ->
            if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN &&
                event.action == KeyEvent.ACTION_DOWN &&
                event.repeatCount == 0
            ) {
                categoryList.scrollToPosition(0)
                categoryList.post {
                    categoryList.findViewHolderForAdapterPosition(0)
                        ?.itemView?.requestFocus()
                }
                true
            } else {
                false
            }
        }
        searchInput.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_DONE) {
                categoryList.scrollToPosition(0)
                categoryList.post {
                    categoryList.findViewHolderForAdapterPosition(0)
                        ?.itemView?.requestFocus()
                }
                true
            } else {
                false
            }
        }

        applyCategoryFilter("")
        dialog = AlertDialog.Builder(activity, R.style.Theme_Debrify_SubtitleDialog)
            .setTitle("Choose category")
            .setView(container)
            .setNegativeButton("Cancel", null)
            .create()
        // Styled looks give the dialog their own (flattened-opaque) panel.
        pickerTokens?.let { t ->
            dialog.window?.setBackgroundDrawable(
                GradientDrawable().apply {
                    cornerRadius = host.dp(18).toFloat()
                    setColor(t.panelOpaque)
                    setStroke(host.dp(1), t.hairline2)
                },
            )
        }
        dialog.setOnShowListener {
            searchInput.requestFocus()
            dialog.window?.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE,
            )
        }
        dialog.show()
    }


    /// "Add to list" checklist for one channel. Reached by long-click once the
    /// user has created a list of their own; before that the same gesture
    /// toggles the favourite outright, exactly as it always did.
    ///
    /// Membership is fetched per channel rather than shipped with every
    /// channel at launch — the launch payload is already capped for size.
    /// Creating a list stays on the Flutter side; this only picks.
    fun showIptvListPicker(entry: IptvChannelEntry) {
        val channel = MainActivity.getAndroidTvPlayerChannel()
        if (channel == null) {
            toggleIptvFavorite(entry)
            return
        }
        val listHeight = minOf(
            host.dp(400),
            (activity.resources.displayMetrics.heightPixels * 0.5f).toInt(),
        )
        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(host.dp(24), host.dp(8), host.dp(24), 0)
        }
        val pickerTokens = host.guideTokens
        val statusText = TextView(activity).apply {
            setPadding(host.dp(2), host.dp(4), host.dp(2), host.dp(8))
            setTextColor(pickerTokens?.fgDim ?: 0xB3FFFFFF.toInt())
            textSize = 13f
            text = "Loading lists…"
        }
        val listView = RecyclerView(activity).apply {
            layoutManager = LinearLayoutManager(
                activity,
                LinearLayoutManager.VERTICAL,
                false,
            )
            isFocusable = true
            clipToPadding = false
            setPadding(0, 0, 0, host.dp(16))
        }
        container.addView(
            statusText,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ),
        )
        container.addView(
            listView,
            LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                listHeight,
            ),
        )

        val membership = mutableSetOf<String>()
        val adapter = IptvListPickerAdapter(
            host.iptvGuideController.iptvLists,
            membership,
            tokens = pickerTokens,
            rowRadiusPx = host.dp(8).toFloat(),
        ) { list ->
            val nowIn = !membership.contains(list.id)
            if (nowIn) membership.add(list.id) else membership.remove(list.id)
            // Favorites drives the star badge in the guide, so keep the row in
            // step when it is the list being toggled.
            if (list.isBuiltin) {
                entry.isFavorite = nowIn
                host.iptvGuideController.iptvChannelAdapter?.notifyFavoriteFor(entry)
            }
            // Removing a channel from the list currently being browsed has to
            // take its row out of the guide too — otherwise it stays there,
            // still selectable, claiming a membership it no longer has.
            if (!nowIn) {
                val browsing = host.iptvSources.firstOrNull { it.id == host.iptvSourceId }
                val browsingThisList = browsing != null &&
                    (browsing.listId == list.id ||
                        (list.isBuiltin && browsing.isFavorites))
                if (browsingThisList) removeIptvGuideRow(entry)
            }
            channel.invokeMethod(
                "setIptvChannelInList",
                hashMapOf<String, Any?>(
                    "listId" to list.id,
                    "inList" to nowIn,
                    "url" to entry.url,
                    "name" to entry.name,
                    "logoUrl" to entry.logoUrl,
                    "group" to entry.group,
                    "sourceId" to entry.sourceId,
                    "channelNumber" to entry.channelNumber,
                    "contentType" to entry.contentType,
                    "duration" to entry.duration,
                    "httpHeaders" to entry.httpHeaders,
                ),
            )
        }
        listView.adapter = adapter

        val dialog = AlertDialog.Builder(activity, R.style.Theme_Debrify_SubtitleDialog)
            .setTitle(entry.name)
            .setView(container)
            .setNegativeButton("Done", null)
            .create()
        pickerTokens?.let { t ->
            dialog.window?.setBackgroundDrawable(
                GradientDrawable().apply {
                    cornerRadius = host.dp(18).toFloat()
                    setColor(t.panelOpaque)
                    setStroke(host.dp(1), t.hairline2)
                },
            )
        }
        dialog.show()

        channel.invokeMethod(
            "getIptvChannelListMembership",
            hashMapOf<String, Any?>("url" to entry.url),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val ids = (result as? List<*>)?.mapNotNull { it as? String }.orEmpty()
                    membership.clear()
                    membership.addAll(ids)
                    statusText.text = "Pick the lists this channel belongs to"
                    // Rows only exist from here on: toggling against an
                    // unloaded membership set would read every list as "not
                    // in", so pressing an already-added list would re-add it
                    // instead of removing it.
                    adapter.setReady(true)
                    listView.post {
                        listView.findViewHolderForAdapterPosition(0)
                            ?.itemView?.requestFocus()
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    statusText.text = "Couldn't load your lists"
                }

                override fun notImplemented() {
                    statusText.text = "Couldn't load your lists"
                }
            },
        )
    }

    /// Drop [entry] from the guide after it left the list being browsed.
    ///
    /// A local removal rather than a re-browse: re-requesting the source would
    /// rebuild the whole window and throw away the user's scroll position and
    /// focus, for a change we already know the shape of. The adapter diffs, so
    /// the row animates out and the rest keep their holders.
    fun removeIptvGuideRow(entry: IptvChannelEntry) {
        // The playing channel is not removable from under the player — it
        // would strand zapping with no current index. Its membership is gone
        // in storage either way; the row simply outlives the session.
        if (entry.isCurrent) return
        val removedFromBrowse = host.iptvGuideController.iptvBrowseChannels.removeAll { it === entry }
        host.iptvGuideController.iptvSearchSavedChannels.removeAll { it === entry }
        if (!removedFromBrowse) return
        host.iptvGuideController.iptvChannelAdapter?.updateChannels(host.iptvGuideController.iptvBrowseChannels.toList())
        host.iptvGuideController.refreshIptvBrowserChrome()
    }

    fun toggleIptvFavorite(entry: IptvChannelEntry) {
        entry.isFavorite = !entry.isFavorite
        if (host.iptvGuideController.iptvAllCategorySearchActive) {
            host.iptvGuideController.iptvSearchSavedChannels
                .filter {
                    it.url == entry.url &&
                        it.name == entry.name &&
                        it.sourceId == entry.sourceId
                }
                .forEach { it.isFavorite = entry.isFavorite }
        }
        host.iptvGuideController.iptvChannelAdapter?.notifyFavoriteFor(entry)
        val args = hashMapOf<String, Any?>(
            "url" to entry.url,
            "name" to entry.name,
            "logoUrl" to entry.logoUrl,
            "group" to entry.group,
            "sourceId" to entry.sourceId,
            "channelNumber" to entry.channelNumber,
            // Without these a movie favourited here would be replayed as a
            // live channel and lose its resume bar — the list view rebuilds
            // rows from stored metadata alone.
            "contentType" to entry.contentType,
            "duration" to entry.duration,
            "httpHeaders" to entry.httpHeaders,
            "isFavorite" to entry.isFavorite,
        )
        MainActivity.getAndroidTvPlayerChannel()?.invokeMethod("setIptvFavorite", args)
        Toast.makeText(
            activity,
            if (entry.isFavorite) "Added to favorites" else "Removed from favorites",
            Toast.LENGTH_SHORT,
        ).show()
    }
}
