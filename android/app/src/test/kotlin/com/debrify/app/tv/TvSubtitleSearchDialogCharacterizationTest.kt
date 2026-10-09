package com.debrify.app.tv

import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.ColorDrawable
import android.text.InputType
import android.text.TextUtils
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.app.AlertDialog
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowToast
import org.robolectric.util.ReflectionHelpers

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSubtitleSearchDialogCharacterizationTest : TvPhase14OriginalTest() {
    private fun dp(value: Int) = (value * activity.resources.displayMetrics.density).toInt()
    private fun sp(value: Int) = value * activity.resources.displayMetrics.scaledDensity
    private fun editor(input: EditText, action: Int, event: KeyEvent? = null): Boolean {
        val editor: Any = ReflectionHelpers.getField(input, "mEditor")
        val content: Any = ReflectionHelpers.getField(editor, "mInputContentType")
        val listener: TextView.OnEditorActionListener? = ReflectionHelpers.getField(content, "onEditorActionListener")
        assertNotNull("Dialog installs its editor action listener", listener)
        return listener!!.onEditorAction(input, action, event)
    }
    private fun search(query: String = "Found film") { showSearch(); this.query().setText(query); searchButton().performClick() }
    private fun focusCancel() { assertTrue(dialog().getButton(AlertDialog.BUTTON_NEGATIVE).requestFocus()) }
    private fun inputs() = descendants().filterIsInstance<EditText>()
    private fun title() = dialog().findViewById<TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString()
    @Test fun noCurrentVideoShowsToastWithoutOpeningDialog() {
        set("payload", null); val previous = org.robolectric.shadows.ShadowDialog.getLatestDialog()
        call("showSearchSubtitleDialog", emptyArray())
        assertSame(previous, org.robolectric.shadows.ShadowDialog.getLatestDialog()); assertEquals("No current video to search", ShadowToast.getTextOfLatestToast())
    }
    @Test fun searchDialogPinsTitleQueryStyleAndContainerGeometry() {
        showSearch(); val query = query(); val container = query.parent as LinearLayout
        assertEquals("Search Movie/Show Subtitles", title()); assertEquals("Movie or show title", query.hint?.toString())
        assertEquals(InputType.TYPE_CLASS_TEXT, query.inputType and InputType.TYPE_MASK_CLASS)
        assertEquals(EditorInfo.IME_ACTION_SEARCH, query.imeOptions and EditorInfo.IME_MASK_ACTION)
        assertEquals(1, query.maxLines); assertEquals(Color.WHITE, query.currentTextColor); assertEquals(0x80FFFFFF.toInt(), query.currentHintTextColor)
        assertEquals(LinearLayout.VERTICAL, container.orientation)
        assertEquals(listOf(dp(24), dp(8), dp(24), 0), listOf(container.paddingLeft, container.paddingTop, container.paddingRight, container.paddingBottom))
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, query.layoutParams.width); assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, query.layoutParams.height)
        assertEquals("Cancel", dialog().getButton(AlertDialog.BUTTON_NEGATIVE).text.toString())
        assertTrue(query.requestFocus()); assertEquals(0, query.selectionStart); assertEquals(query.text.length, query.selectionEnd)
    }
    @Test fun searchButtonSpinnerAndStatusStylesArePinned() {
        showSearch(); val button = searchButton(); val progress = descendants().filterIsInstance<ProgressBar>().single(); val row = button.parent as LinearLayout
        assertEquals("Search", button.text.toString()); assertTrue(button.isFocusable); assertEquals(Color.WHITE, button.currentTextColor)
        assertEquals(com.debrify.app.R.drawable.subtitle_search_button_bg, org.robolectric.Shadows.shadowOf(button.background).createdFromResId);
        assertEquals("SEARCH", (button.transformationMethod?.getTransformation(button.text, button) ?: button.text).toString()); assertNull(button.stateListAnimator); assertEquals(dp(44), button.minimumHeight)
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, row.layoutParams.width); assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, row.layoutParams.height)
        assertEquals(LinearLayout.HORIZONTAL, row.orientation); assertEquals(android.view.Gravity.CENTER_VERTICAL or android.view.Gravity.START, row.gravity)
        assertEquals(listOf(0, dp(12), 0, dp(8)), listOf(row.paddingLeft, row.paddingTop, row.paddingRight, row.paddingBottom))
        assertEquals(0, button.layoutParams.width); assertEquals(1f, (button.layoutParams as LinearLayout.LayoutParams).weight, 0f)
        assertTrue(progress.isIndeterminate); assertEquals(View.GONE, progress.visibility)
        assertEquals(dp(48), progress.layoutParams.width); assertEquals(dp(48), progress.layoutParams.height)
        assertEquals(dp(16), (progress.layoutParams as LinearLayout.LayoutParams).leftMargin)
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, status().layoutParams.width); assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, status().layoutParams.height)
        assertEquals("Find subtitles by choosing the correct title.", status().text.toString()); assertEquals(0xB3FFFFFF.toInt(), status().currentTextColor); assertEquals(dp(8), status().paddingBottom)
    }
    @Test fun resultListPinsFocusSelectorDividerPaddingAndHeight() {
        showSearch(); val list = resultList()
        assertFalse("Empty AdapterView temporarily disables focus", list.isFocusable)
        searchButton().performClick(); endpoint.success("searchSubtitleCatalogs", catalog(result())); layoutDialog()
        assertTrue(list.isFocusable); assertTrue(list.isFocusableInTouchMode);
        assertEquals(com.debrify.app.R.drawable.subtitle_catalog_row_selector, org.robolectric.Shadows.shadowOf(list.selector).createdFromResId)
        assertFalse(ReflectionHelpers.getField<Boolean>(list, "mDrawSelectorOnTop"))
        assertEquals(0x14FFFFFF, (list.divider as ColorDrawable).color); assertEquals(1, list.dividerHeight)
        assertFalse(list.clipToPadding); assertEquals(listOf(0, 0, 0, dp(48)), listOf(list.paddingLeft, list.paddingTop, list.paddingRight, list.paddingBottom))
        assertNull(list.emptyView); assertEquals(dp(360), list.layoutParams.height); assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, list.layoutParams.width)
        assertEquals(1, list.adapter.count)
    }
    @Test fun emptyQueryClearsExistingResultsAndFocusesQueryWithoutSending() {
        search(); endpoint.success("searchSubtitleCatalogs", catalog(result())); query().setText(" \n ")
        val count = endpoint.requests.size; focusCancel(); searchButton().performClick()
        assertEquals(count, endpoint.requests.size); assertEquals(0, resultList().adapter.count); assertEquals(0, resultList().count)
        assertEquals("Enter a title to search.", status().text.toString()); assertTrue(query().hasFocus())
    }
    @Test fun zeroResultReplyClearsRowsAndReturnsFocusToSearchButton() {
        search(); endpoint.success("searchSubtitleCatalogs", catalog(result())); searchButton().performClick(); focusCancel(); endpoint.success("searchSubtitleCatalogs", emptyList<Any>())
        assertEquals(0, resultList().adapter.count); assertEquals(0, resultList().count); assertEquals("No matching movie/show results found.", status().text.toString()); assertTrue(searchButton().hasFocus())
    }
    @Test fun multipleResultReplySetsPluralCountAndSelectsFirstRow() {
        search(); endpoint.success("searchSubtitleCatalogs", catalog(result(), result(name = "Second", imdb = "tt142")))
        layoutDialog(); resultList().setSelection(1); layoutDialog(); assertEquals(1, resultList().selectedItemPosition)
        searchButton().performClick(); focusCancel(); endpoint.success("searchSubtitleCatalogs", catalog(result(), result(name = "Second", imdb = "tt142")))
        layoutDialog(); assertEquals(2, resultList().adapter.count); assertEquals("2 results", status().text.toString())
        assertTrue(resultList().hasFocus()); assertEquals(0, resultList().selectedItemPosition)
    }
    @Test fun encodedNullCatalogReplyIsAnEmptySuccessfulResult() {
        search(); endpoint.success("searchSubtitleCatalogs", null)
        assertEquals("No matching movie/show results found.", status().text.toString()); assertTrue(searchButton().isEnabled)
        assertEquals(View.GONE, descendants().filterIsInstance<ProgressBar>().single().visibility)
    }
    @Test fun serverErrorClearsOldResultsShowsMessageAndRefocusesButton() {
        search(); endpoint.success("searchSubtitleCatalogs", catalog(result())); searchButton().performClick(); focusCancel(); endpoint.error("searchSubtitleCatalogs", "Server declined")
        assertEquals(0, resultList().adapter.count); assertEquals(0, resultList().count); assertEquals("Server declined", status().text.toString()); assertTrue(searchButton().hasFocus()); assertTrue(query().isEnabled)
    }
    @Test fun serverErrorWithNullMessageUsesExactDefault() {
        search(); endpoint.error("searchSubtitleCatalogs", null); assertEquals("Subtitle search failed.", status().text.toString()); assertTrue(searchButton().isEnabled)
    }
    @Test fun notImplementedUsesExactUnavailableText() {
        search(); endpoint.unavailable("searchSubtitleCatalogs"); assertEquals("Subtitle search is unavailable.", status().text.toString()); assertTrue(query().isEnabled)
    }
    @Test fun dismissedDialogIgnoresBothLateSuccessAndError() {
        search(); val before = status(); val button = searchButton(); val list = resultList(); dialog().dismiss()
        endpoint.success("searchSubtitleCatalogs", catalog(result())); assertEquals("Searching...", before.text.toString()); assertEquals(0, list.adapter.count); assertFalse(button.isEnabled)
        endpoint.error("searchSubtitleCatalogs", "Server declined"); assertEquals("Searching...", before.text.toString()); assertFalse(button.isEnabled)
    }
    @Test fun queryImeSearchAndReleasedEnterInvokeSearchWhileOtherActionsDoNot() {
        showSearch(); val query = query()
        assertFalse(editor(query, EditorInfo.IME_ACTION_DONE)); assertFalse(editor(query, EditorInfo.IME_ACTION_NONE, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER)))
        assertFalse(editor(query, EditorInfo.IME_ACTION_NONE, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DPAD_CENTER)))
        assertTrue(endpoint.requests.isEmpty())
        assertTrue(editor(query, EditorInfo.IME_ACTION_SEARCH)); assertEquals(1, endpoint.requests.count { it.call.method == "searchSubtitleCatalogs" })
        endpoint.success("searchSubtitleCatalogs", null)
        assertTrue(editor(query, EditorInfo.IME_ACTION_NONE, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER)))
        assertEquals(2, endpoint.requests.count { it.call.method == "searchSubtitleCatalogs" })
    }
    @Test fun movieResultClickDismissesAndAppliesManualIdentity() {
        search(); endpoint.success("searchSubtitleCatalogs", catalog(result())); val shown = dialog()
        resultList().performItemClick(null, 0, 0); assertFalse(shown.isShowing); assertEquals("tt141", field("manualSubtitleImdbId")); assertEquals("movie", field("manualSubtitleType"))
    }
    @Test fun resolvedSeriesResultClickUsesItemSeasonAndEpisode() {
        model().items[0] = item().copy(season = 3, episode = 8)
        search(); endpoint.success("searchSubtitleCatalogs", catalog(result("series"))); val shown = dialog(); resultList().performItemClick(null, 0, 0)
        assertFalse(shown.isShowing); assertEquals(3, field("manualSubtitleSeason")); assertEquals(8, field("manualSubtitleEpisode"))
    }
    @Test fun resultClickAfterCurrentVideoDisappearsLeavesDialogAndShowsToast() {
        search(); endpoint.success("searchSubtitleCatalogs", catalog(result())); set("payload", null)
        resultList().performItemClick(null, 0, 0); assertTrue(dialog().isShowing); assertEquals("No current video to search", ShadowToast.getTextOfLatestToast()); assertNull(field("manualSubtitleImdbId"))
    }
    @Test fun adapterBindsExactTitleDetailFontsPaddingAndRecycledChildren() {
        val results = mutableListOf(result(), result("series", "Show", "tt142"))
        @Suppress("UNCHECKED_CAST") val adapter = call("createSubtitleCatalogResultAdapter", arrayOf(listType), results) as android.widget.ArrayAdapter<SubtitleCatalogResult>
        val row = adapter.getView(0, null, LinearLayout(activity)) as LinearLayout
        assertSame(activity, adapter.context); assertSame(activity, row.context)
        assertEquals(LinearLayout.VERTICAL, row.orientation); assertEquals(dp(72), row.minimumHeight)
        assertEquals(listOf(dp(20), dp(12), dp(20), dp(12)), listOf(row.paddingLeft, row.paddingTop, row.paddingRight, row.paddingBottom))
        val title = row.getChildAt(0) as TextView; val detail = row.getChildAt(1) as TextView
        assertEquals("Found film (2024)", title.text.toString()); assertEquals("Movie · Catalog · tt141", detail.text.toString())
        assertEquals(sp(18), title.textSize, 0f); assertEquals(sp(14), detail.textSize, 0f)
        assertEquals(Color.WHITE, title.currentTextColor); assertEquals(Color.LTGRAY, detail.currentTextColor); assertEquals(Typeface.BOLD, title.typeface.style)
        for (text in listOf(title, detail)) { assertEquals(1, text.maxLines); assertEquals(TextUtils.TruncateAt.END, text.ellipsize); assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, text.layoutParams.width); assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, text.layoutParams.height) }
        row.addView(TextView(activity)); assertSame(row, adapter.getView(1, row, LinearLayout(activity))); assertEquals(2, row.childCount)
        assertEquals("Show (2024)", (row.getChildAt(0) as TextView).text.toString()); assertEquals("Series · Catalog · tt142", (row.getChildAt(1) as TextView).text.toString())
        assertTrue(adapter.getView(0, View(activity), LinearLayout(activity)) is LinearLayout)
    }
    @Test fun seasonPromptPinsTitleInputsDefaultValuesAndGeometry() {
        prompt(); val inputs = inputs(); val season = inputs[0]; val episode = inputs[1]
        val container = season.parent.parent as LinearLayout
        assertEquals(LinearLayout.VERTICAL, container.orientation); assertEquals(listOf(dp(24), dp(8), dp(24), 0), listOf(container.paddingLeft, container.paddingTop, container.paddingRight, container.paddingBottom))
        val heading = container.getChildAt(0) as TextView
        assertEquals("Found film (2024)", heading.text.toString()); assertEquals(sp(18), heading.textSize, 0f); assertEquals(dp(12), heading.paddingBottom)
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, heading.layoutParams.width); assertEquals(ViewGroup.LayoutParams.WRAP_CONTENT, heading.layoutParams.height)
        assertEquals(ViewGroup.LayoutParams.MATCH_PARENT, (season.parent as LinearLayout).layoutParams.width)
        assertEquals("Series Episode", title()); assertEquals(listOf("Season", "Episode"), inputs.map { it.hint.toString() }); assertEquals(listOf("1", "1"), inputs.map { it.text.toString() })
        assertEquals(EditorInfo.IME_ACTION_NEXT, season.imeOptions); assertEquals(EditorInfo.IME_ACTION_DONE, episode.imeOptions)
        for (input in inputs) { assertEquals(InputType.TYPE_CLASS_NUMBER, input.inputType); assertEquals(Color.WHITE, input.currentTextColor); assertEquals(0x80FFFFFF.toInt(), input.currentHintTextColor); assertEquals(0, input.layoutParams.width); assertEquals(1f, (input.layoutParams as LinearLayout.LayoutParams).weight, 0f) }
        assertTrue("Prompt initially focuses the season field", season.hasFocus())
        assertEquals(0, season.selectionStart); assertEquals(season.text.length, season.selectionEnd)
        assertTrue(episode.requestFocus()); assertEquals(0, episode.selectionStart); assertEquals(episode.text.length, episode.selectionEnd)
        assertEquals(dp(12), (season.layoutParams as LinearLayout.LayoutParams).rightMargin)
        assertEquals(LinearLayout.HORIZONTAL, (season.parent as LinearLayout).orientation)
        assertEquals("Search", dialog().getButton(AlertDialog.BUTTON_POSITIVE).text.toString()); assertEquals("Cancel", dialog().getButton(AlertDialog.BUTTON_NEGATIVE).text.toString())
    }
    @Test fun seasonPromptPrefersCurrentItemNumbersOverManualFallback() {
        model().items[0] = item().copy(season = 4, episode = 7); set("manualSubtitleSeason", 8); set("manualSubtitleEpisode", 9); prompt()
        assertEquals(listOf("4", "7"), inputs().map { it.text.toString() })
    }
    @Test fun seasonPromptUsesManualNumbersWhenItemNumbersAreAbsent() {
        set("manualSubtitleSeason", 8); set("manualSubtitleEpisode", 9); prompt(); assertEquals(listOf("8", "9"), inputs().map { it.text.toString() })
    }
    @Test fun invalidSeasonAndEpisodeBoundariesKeepPromptShownAndTokenUnchanged() {
        prompt(); val inputs = inputs(); val before = token()
        for ((season, episode) in listOf("" to "1", "1" to "", "0" to "1", "1" to "0", "-1" to "1", "1" to "-1", "bad" to "1", "1" to "bad")) {
            inputs[0].setText(season); inputs[1].setText(episode); dialog().getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            assertTrue(dialog().isShowing); assertEquals(before, token()); assertEquals("Enter a valid season and episode", ShadowToast.getTextOfLatestToast())
        }
    }
    @Test fun episodeImeDoneAndReleasedEnterSubmitWhileOtherActionsDoNot() {
        prompt(); val input = inputs()[1]
        assertFalse(editor(input, EditorInfo.IME_ACTION_SEARCH)); assertFalse(editor(input, EditorInfo.IME_ACTION_NONE, KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER)))
        assertFalse(editor(input, EditorInfo.IME_ACTION_NONE, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_DPAD_CENTER))); assertTrue(dialog().isShowing)
        assertTrue(editor(input, EditorInfo.IME_ACTION_DONE)); assertFalse(dialog().isShowing); assertEquals(1, field("manualSubtitleSeason")); assertEquals(1, field("manualSubtitleEpisode"))
        prompt(); assertTrue(editor(inputs()[1], EditorInfo.IME_ACTION_NONE, KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER))); assertFalse(dialog().isShowing)
    }
    @Test fun cancelButtonsDismissWithoutChangingIdentity() {
        val before = token(); showSearch(); dialog().getButton(AlertDialog.BUTTON_NEGATIVE).performClick(); idle(); assertFalse(dialog().isShowing); assertEquals(before, token())
        prompt(); dialog().getButton(AlertDialog.BUTTON_NEGATIVE).performClick(); idle(); assertFalse(dialog().isShowing); assertEquals(before, token()); assertNull(field("manualSubtitleImdbId"))
    }
}
