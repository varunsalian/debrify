package com.debrify.app.tv

import androidx.appcompat.app.AlertDialog
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowDialog

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvAudioMenuCharacterizationTest : TvPhase15OriginalTest() {
    private fun group(type: String = "audio/mp4a-latm", selected: Int = -1, vararg languages: String): Tracks.Group {
        val formats = languages.map { Format.Builder().setSampleMimeType(type).setLanguage(it).setChannelCount(2).build() }
        return Tracks.Group(TrackGroup(*formats.toTypedArray()), false,
            IntArray(formats.size) { C.FORMAT_HANDLED }, BooleanArray(formats.size) { it == selected })
    }
    @Suppress("UNCHECKED_CAST") private fun rows() = call("umAudioTracks", emptyArray()) as List<Pair<String, TrackSelectionOverride?>>
    private fun selected() = call("umAudioSelectedIndex", emptyArray()) as Int
    private fun ts() = field("trackSelector") as DefaultTrackSelector
    private fun showDialog() { call("showAudioTrackDialog", emptyArray()) }
    private fun dialog(): AlertDialog { val value = ShadowDialog.getLatestDialog(); assertNotNull("installed callback shows dialog", value); return value as AlertDialog }
    private fun pick(index: Int) {
        val list = dialog().listView
        list.performItemClick(null, index, list.adapter.getItemId(index))
    }
    private fun override(): TrackSelectionOverride { assertEquals("exactly one chosen audio override", 1, ts().parameters.overrides.size); return ts().parameters.overrides.values.single() }
    @Test fun noPlayerReturnsOnlyOffAndSelectedIndexZero() {
        set("player", null)
        assertEquals(listOf("Off" to null), rows()); assertEquals(0, selected())
    }
    @Test fun tracksFlattenAudioGroupsInOrderAndIgnoreOtherTypes() {
        val first = group(languages = arrayOf("en", "fr"))
        val other = group(type = "text/vtt", languages = arrayOf("de"))
        val last = group(languages = arrayOf("es"))
        tracks = Tracks(listOf(first, other, last)); val values = rows()
        assertEquals(4, values.size); assertEquals("Off", values[0].first); assertNull(values[0].second)
        assertEquals(listOf(first.mediaTrackGroup, first.mediaTrackGroup, last.mediaTrackGroup), values.drop(1).map { it.second!!.mediaTrackGroup })
        assertEquals(listOf(listOf(0), listOf(1), listOf(0)), values.drop(1).map { it.second!!.trackIndices.toList() })
        assertEquals(listOf("EN · 2ch", "FR · 2ch", "ES · 2ch"), values.drop(1).map { it.first })
    }
    @Test fun selectedIndexCountsEveryAudioTrackButNeverNonAudioTracks() {
        val first = group(languages = arrayOf("en", "fr"))
        tracks = Tracks(listOf(first, group(type = "video/avc", selected = 0, languages = arrayOf("und")), group(selected = 1, languages = arrayOf("de", "es"))))
        assertEquals(4, selected())
        tracks = Tracks(listOf(group(selected = 0, languages = arrayOf("en", "fr")), first)); assertEquals(1, selected())
        tracks = Tracks(listOf(first)); assertEquals(0, selected())
    }
    @Test fun audioMenuWithoutTracksHasOneDisabledExactPlaceholder() {
        val value = model("umAudioModel")
        assertEquals("AUDIO", value.col2Title); assertEquals("Audio tracks", value.col3Title)
        assertEquals(listOf("Audio track", "Night mode"), value.col2.map { it.title })
        assertEquals(listOf("audio", "night"), value.col2.map { it.tag }); assertEquals("Off", value.col2[1].value)
        assertEquals("No audio tracks available", value.col3.single().title); assertFalse(value.col3.single().enabled)
        assertNull(value.col3.single().onOk)
    }
    @Test fun nightMenuPinsEightRowsAndInvokesTheirOriginalApplyLogic() {
        set("nightModeIndex", 3); val value = model("umAudioModel", 1)
        assertEquals("Night mode · loudness", value.col3Title)
        val labels = listOf("Off", "Low", "Medium", "High", "Higher", "Extreme", "Max", "Sleeping Baby")
        assertEquals(labels, value.col3.map { it.title }); assertEquals(listOf(3), value.col3.indices.filter { value.col3[it].selected })
        routing().update(true, false); value.col3[6].onOk!!.invoke()
        assertEquals(6, field("nightModeIndex")); assertEquals("Max", button("nightModeButton").text.toString()); assertEquals("Night Mode: Max", toast())
        assertEquals(listOf(3000, 3000), TvPhase15Effects.effects.single().gains)
    }
    @Test fun unknownAudioSubIndexStillBuildsTheTrackBranch() {
        tracks = Tracks(listOf(group(selected = 1, languages = arrayOf("en", "fr"))))
        val value = model("umAudioModel", 99)
        assertEquals("Audio tracks", value.col3Title); assertEquals(3, value.col3.size)
        assertEquals(listOf(false, false, true), value.col3.map { it.selected })
        assertEquals(listOf("Off", "EN · 2ch", "FR · 2ch"), value.col3.map { it.title })
    }
    @Test fun audioMenuOnActionSetsOverrideEnablesAudioAndPersistsSeriesLanguage() {
        val audio = group(languages = arrayOf("en", "fr")); tracks = Tracks(listOf(audio))
        set("iptvSeriesAudioKey", "series-key"); val value = model("umAudioModel")
        ts().parameters = ts().parameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true).build()
        value.col3[2].onOk!!.invoke()
        assertFalse(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO)); assertEquals(audio.mediaTrackGroup, override().mediaTrackGroup)
        assertEquals(listOf(1), override().trackIndices.toList()); assertEquals("fr", field("iptvPreferredAudioLang"))
        val saved = messenger.requests.single { it.call.method == "saveIptvSeriesAudio" }
        assertEquals(mapOf("seriesKey" to "series-key", "lang" to "fr"), saved.call.arguments)
    }
    @Test fun audioMenuOffDisablesAudioAndDoesNotPersistAReplacementLanguage() {
        tracks = Tracks(listOf(group(selected = 0, languages = arrayOf("en"))))
        set("iptvSeriesAudioKey", "series-key"); set("iptvPreferredAudioLang", "de")
        model("umAudioModel").col3[0].onOk!!.invoke()
        assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO)); assertEquals("de", field("iptvPreferredAudioLang"))
        assertFalse(messenger.requests.any { it.call.method == "saveIptvSeriesAudio" })
    }
    @Test fun audioMenuActionReadsReplacementTracksAtClickTime() {
        val first = group(languages = arrayOf("en")); tracks = Tracks(listOf(first)); val value = model("umAudioModel")
        val replacement = group(languages = arrayOf("fr")); tracks = Tracks(listOf(replacement))
        value.col3[1].onOk!!.invoke(); assertEquals(replacement.mediaTrackGroup, override().mediaTrackGroup)
        assertNotEquals(first.mediaTrackGroup, override().mediaTrackGroup)
    }
    @Test fun vanishedAudioRowFallsBackToOffAtClickTime() {
        tracks = Tracks(listOf(group(languages = arrayOf("en")))); val value = model("umAudioModel")
        tracks = Tracks.EMPTY; value.col3[1].onOk!!.invoke()
        assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO))
    }
    @Test fun audioMenuActionReadsTheReplacementTrackSelectorAtClickTime() {
        tracks = Tracks(listOf(group(languages = arrayOf("en")))); val value = model("umAudioModel")
        val old = ts(); val replacement = DefaultTrackSelector(activity); set("trackSelector", replacement)
        value.col3[1].onOk!!.invoke()
        assertTrue(old.parameters.overrides.isEmpty()); assertEquals(1, replacement.parameters.overrides.size)
    }
    @Test fun nullSelectorAtMenuClickDoesNotApplyOrPersistLanguage() {
        tracks = Tracks(listOf(group(languages = arrayOf("en")))); val value = model("umAudioModel")
        val old = ts(); set("trackSelector", null); set("iptvSeriesAudioKey", "series-key")
        value.col3[1].onOk!!.invoke(); assertTrue(old.parameters.overrides.isEmpty())
        assertFalse(messenger.requests.any { it.call.method == "saveIptvSeriesAudio" })
    }
    @Test fun audioDialogWithoutRealTracksShowsTheExactToastInsteadOfADialog() {
        showDialog(); assertEquals("No audio tracks available", toast()); assertNull(ShadowDialog.getLatestDialog())
    }
    @Test fun audioDialogRejectsMissingPlayerOrSelectorWithoutShowing() {
        org.robolectric.shadows.ShadowToast.reset()
        val old = ts(); set("trackSelector", null); showDialog(); assertNull(ShadowDialog.getLatestDialog()); assertNull(toast())
        set("trackSelector", old); set("player", null); showDialog(); assertNull(ShadowDialog.getLatestDialog()); assertNull(toast())
    }
    @Test fun dialogChoiceUsesTheCapturedTracksAndSelectorRatherThanReplacementState() {
        val audio = group(languages = arrayOf("en", "fr")); tracks = Tracks(listOf(audio)); val old = ts()
        old.parameters = old.parameters.buildUpon().setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, true).build()
        showDialog(); assertTrue(dialog().isShowing)
        assertEquals("Select Audio Track", (dialog().findViewById<android.widget.TextView>(androidx.appcompat.R.id.alertTitle))!!.text.toString())
        assertEquals(3, dialog().listView.adapter.count)
        assertEquals(listOf("Off", "EN · 2ch", "FR · 2ch"), (0 until dialog().listView.adapter.count).map { dialog().listView.adapter.getItem(it).toString() })
        assertEquals(android.view.View.GONE, dialog().getButton(AlertDialog.BUTTON_NEGATIVE).visibility)
        tracks = Tracks(listOf(group(languages = arrayOf("de")))); val replacement = DefaultTrackSelector(activity); set("trackSelector", replacement)
        set("iptvSeriesAudioKey", "series-key"); pick(2)
        assertEquals("dialog applies exactly one override to the captured selector", 1, old.parameters.overrides.size)
        val chosen = old.parameters.overrides.values.single()
        assertEquals(audio.mediaTrackGroup, chosen.mediaTrackGroup); assertEquals(listOf(1), chosen.trackIndices.toList())
        assertTrue(replacement.parameters.overrides.isEmpty()); assertEquals("fr", field("iptvPreferredAudioLang"))
        assertFalse("choosing a track re-enables the captured selector", old.parameters.disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO))
    }
    @Test fun dialogOffDisablesItsCapturedSelector() {
        tracks = Tracks(listOf(group(selected = 0, languages = arrayOf("en"))))
        showDialog(); pick(0); assertTrue(ts().parameters.disabledTrackTypes.contains(C.TRACK_TYPE_AUDIO))
    }
}
