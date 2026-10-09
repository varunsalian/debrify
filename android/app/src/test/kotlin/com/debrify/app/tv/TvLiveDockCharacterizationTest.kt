package com.debrify.app.tv

import android.graphics.Typeface
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.core.widget.TextViewCompat
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvLiveDockCharacterizationTest : TvPhase15LiveOriginalTest() {
    override val guide = GuideStyle.GLASS
    private fun liveSetup() = call("setupIptvControls", emptyArray())
    private fun showControls() { set("controlsMenuVisible", true); (field("controlsOverlay") as View).visibility = View.VISIBLE }
    private fun hidden() = assertFalse(field("controlsMenuVisible") as Boolean)
    @Test fun missingEntryUsesTheLiveVisibilityAndSeekResetPath() {
        set("cinemaSeekMode", true); set("cinemaSeekWasPlaying", true)
        presentation(null)
        assertEquals(View.GONE, button("speedButton").visibility)
        assertEquals(View.VISIBLE, button("nightModeButton").visibility)
        assertEquals(View.VISIBLE, button("iptvJumpButton").visibility)
        assertFalse(field("cinemaSeekMode") as Boolean); assertFalse(field("cinemaSeekWasPlaying") as Boolean)
        assertEquals(View.INVISIBLE, (field("cinemaProgressThumb") as View).visibility)
        assertEquals(View.GONE, (field("cinemaSpeedIndicator") as View).visibility)
    }
    @Test fun liveArchiveProgressRequiresBothActiveAndTimelineVisible() {
        val seekTexts = mutableListOf<String>()
        button("iptvStartOverSeekButton").addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { seekTexts.add(s.toString()) }
            override fun afterTextChanged(s: android.text.Editable?) {}
        })
        for (active in listOf(false, true)) for (visible in listOf(false, true)) {
            set("iptvStartOverActive", active); set("iptvStartOverTimelineVisible", visible); set("iptvStartOverLoading", visible)
            for (name in listOf("iptvStartOverButton", "iptvStartOverSeekButton")) {
                button(name).text = "Stale"; button(name).contentDescription = "Stale"; button(name).visibility = View.INVISIBLE
            }
            seekTexts.clear()
            presentation(channel())
            val startText = if (visible) "Preparing…" else if (active) "Go Live" else "Start Over"
            assertEquals(startText, button("iptvStartOverButton").text.toString())
            assertEquals(if (active) View.VISIBLE else View.GONE, button("iptvStartOverButton").visibility)
            assertEquals(active && !visible, button("iptvStartOverButton").isEnabled)
            assertEquals(if (visible) "Preparing start over" else if (active) "Return to live channel" else "Start programme from beginning", button("iptvStartOverButton").contentDescription.toString())
            val seekText = if (visible) "Hide Timeline" else "Seek"
            assertEquals(listOf(seekText, seekText), seekTexts) // Button update and explicit presentation refresh both run.
            assertEquals(if (active) View.VISIBLE else View.GONE, button("iptvStartOverSeekButton").visibility)
            assertEquals(active && !visible, button("iptvStartOverSeekButton").isEnabled)
            assertEquals(if (visible) "Hide start over timeline" else "Show start over timeline", button("iptvStartOverSeekButton").contentDescription.toString())
            val expected = if (active && visible) View.VISIBLE else View.GONE
            for (name in listOf("cinemaProgressContainer", "debrifyTimeCurrent", "debrifyTimeTotal"))
                assertEquals("$name active=$active visible=$visible", expected, (field(name) as View).visibility)
        }
    }
    @Test fun vodProgressIsVisibleEvenWithoutAnyStartOverState() {
        set("iptvStartOverActive", false); set("iptvStartOverTimelineVisible", false)
        presentation(channel(live = false))
        for (name in listOf("cinemaProgressContainer", "debrifyTimeCurrent", "debrifyTimeTotal")) assertEquals(View.VISIBLE, (field(name) as View).visibility)
        assertEquals(View.VISIBLE, button("speedButton").visibility)
        assertEquals(View.GONE, button("iptvJumpButton").visibility)
        assertEquals(View.GONE, button("iptvRecordButton").visibility)
    }
    @Test fun liveSeekFocusIsTransferredToPauseButOtherFocusIsPreserved() {
        pv().showController(); (field("controlsOverlay") as View).visibility = View.VISIBLE
        val progress = field("cinemaProgressContainer") as View
        progress.visibility = View.VISIBLE; progress.isFocusable = true; progress.isFocusableInTouchMode = true; layout()
        progress.requestFocus(); org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(progress); assertSame(progress, activity.currentFocus)
        presentation(channel()); assertTrue(button("pauseButton").hasFocus())
        button("audioButton").requestFocus(); org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(button("audioButton")); presentation(channel()); assertTrue(button("audioButton").hasFocus())
    }
    @Test fun vodSetupHidesOnlyTheGuideNavigationAndKeepsExistingClickListeners() {
        iptv(channel(live = false)); val pause = button("pauseButton").onFocusChangeListener
        val background = button("iptvPrevButton").background
        val clickBefore = org.robolectric.Shadows.shadowOf(button("iptvNextButton")).onClickListener
        view(R.id.debrify_random_button)!!.visibility = View.VISIBLE
        for (name in listOf("iptvGuideButton", "iptvPrevButton", "iptvNextButton")) button(name).visibility = View.VISIBLE
        val previousGuide = button("iptvGuideButton")
        val observedGuide = object : androidx.appcompat.widget.AppCompatButton(activity) {
            var recording = false
            val writes = mutableListOf<Int>()
            override fun setVisibility(visibility: Int) {
                if (recording) writes.add(visibility)
                super.setVisibility(visibility)
            }
        }.apply {
            id = previousGuide.id; text = previousGuide.text; layoutParams = previousGuide.layoutParams
            onFocusChangeListener = previousGuide.onFocusChangeListener
            setOnClickListener(org.robolectric.Shadows.shadowOf(previousGuide).onClickListener)
        }
        val parent = previousGuide.parent as ViewGroup; val index = parent.indexOfChild(previousGuide)
        parent.removeView(previousGuide); parent.addView(observedGuide, index)
        @Suppress("UNCHECKED_CAST")
        val order = field("originalControlDockOrder") as List<View>
        set("originalControlDockOrder", order.map { if (it === previousGuide) observedGuide else it })
        set("iptvGuideButton", observedGuide); observedGuide.recording = true
        liveSetup()
        assertEquals("guide is hidden before restyling and remains hidden in the final presentation", listOf(View.GONE, View.GONE), observedGuide.writes)
        for (name in listOf("iptvGuideButton", "iptvPrevButton", "iptvNextButton")) assertEquals(View.GONE, button(name).visibility)
        assertEquals(View.GONE, view(R.id.debrify_random_button)!!.visibility)
        assertSame(pause, button("pauseButton").onFocusChangeListener)
        assertNotSame(background, button("iptvPrevButton").background) // Presentation restores cinema resources.
        movie()
        set("isIptvMode", false); showControls(); button("iptvNextButton").performClick(); hidden(); assertEquals(0, field("currentIptvIndex")); assertTrue(probe.events.isEmpty())
        assertSame(clickBefore, org.robolectric.Shadows.shadowOf(button("iptvNextButton")).onClickListener)
    }
    @Test fun liveSetupInstallsChannelMinusPlusAndRecordingCallbacks() {
        iptv(channel()); set("iptvChannels", mutableListOf(channel(), channel().copy(index = 1, channelNumber = 8, name = "Beta", url = "https://phase15.invalid/beta.ts")))
        liveSetup()
        assertEquals("CH -", button("iptvPrevButton").text.toString()); assertEquals("CH +", button("iptvNextButton").text.toString())
        showControls(); button("iptvNextButton").performClick(); hidden()
        assertEquals(1, field("currentIptvIndex")); assertEquals("https://phase15.invalid/beta.ts", field("currentIptvStreamUrl"))
        messenger.requests.clear(); set("currentIptvIndex", 1)
        showControls(); button("iptvPrevButton").performClick(); hidden()
        assertEquals(0, field("currentIptvIndex")); assertEquals(channel().url, field("currentIptvStreamUrl"))
    }
    @Test fun liveRecordingClickHidesTheDockAndRoutesToThePreQPermissionFlow() {
        iptv(channel()); liveSetup(); showControls(); button("iptvRecordButton").performClick(); hidden()
        assertTrue("permission path produces the original recording message", toast() == "Allow storage access, then press Record again")
    }
    @Test fun jumpClickHidesDockAndShowsTheNumberInput() {
        iptv(channel()); showControls(); button("iptvJumpButton").performClick(); hidden()
        val shown = org.robolectric.shadows.ShadowDialog.getLatestDialog()
        assertNotNull("jump callback shows the channel-number dialog", shown)
        val dialog = shown as androidx.appcompat.app.AlertDialog
        assertTrue(dialog.isShowing)
        assertEquals("Jump to channel", dialog.findViewById<android.widget.TextView>(androidx.appcompat.R.id.alertTitle)!!.text.toString())
    }
    @Test fun startOverAndSeekClickRouteIntoTheirTimelineState() {
        iptv(channel().copy(epgNowTitle = "Programme", epgNowStartMs = programme().startMs, epgNowStopMs = programme().stopMs, epgNowHasArchive = true, epgLoaded = true, epgCatchupMetadataLoaded = true))
        showControls(); button("iptvStartOverButton").performClick(); hidden()
        assertTrue(requests("requestIptvCatchup").isNotEmpty())
        set("iptvStartOverActive", true); set("iptvStartOverTimelineVisible", false); probe.duration = 0
        button("iptvStartOverSeekButton").performClick()
        assertEquals("Timeline is still loading", toast())
    }
    @Test fun vodPresentationHidesAnOpenGuideAndLivePresentationLeavesItOpen() {
        iptv(channel()); call("showIptvGuide", emptyArray()); assertTrue(field("iptvGuideVisible") as Boolean)
        presentation(channel()); assertTrue(field("iptvGuideVisible") as Boolean)
        presentation(channel(live = false)); assertFalse(field("iptvGuideVisible") as Boolean)
    }
    @Test fun repeatedLiveOrderDoesNotDetachAnyChildAndPreservesHiddenExtras() {
        presentation(channel()); val order = children(); val changes = mutableListOf<String>()
        dock().setOnHierarchyChangeListener(object : ViewGroup.OnHierarchyChangeListener {
            override fun onChildViewAdded(parent: View, child: View) { changes.add("add") }
            override fun onChildViewRemoved(parent: View, child: View) { changes.add("remove") }
        })
        presentation(channel()); assertEquals(order, children()); assertTrue(changes.isEmpty())
        assertTrue(children().contains(button("speedButton"))); assertEquals(View.GONE, button("speedButton").visibility)
    }
    @Test fun emptyOriginalOrderGuardDoesNotDiscardTheExistingDock() {
        val before = children(); set("originalControlDockOrder", emptyList<View>())
        call("restoreOriginalControlDockOrder", emptyArray()); assertEquals(before, children())
    }
    @Test fun missingDockGuardsDoNotTouchDetachedChildren() {
        val d = dock(); val before = children(); d.id = View.NO_ID
        try {
            call("arrangeLiveIptvControlDock", emptyArray()); call("restoreOriginalControlDockOrder", emptyArray())
        } catch (failure: Exception) { fail("Missing dock must leave detached children untouched: $failure") }
        assertEquals(before, List(d.childCount) { d.getChildAt(it) })
    }
    @Test fun iconAndTypefaceRestoreUseTheirOwnPresenceChecks() {
        call("applyLiveIptvControlStyle", emptyArray()); val b = button("audioButton")
        @Suppress("UNCHECKED_CAST") val icons = field("cinemaIconTints") as MutableMap<View, android.content.res.ColorStateList?>
        @Suppress("UNCHECKED_CAST") val fonts = field("cinemaButtonTypefaces") as MutableMap<View, Typeface?>
        val tint = android.content.res.ColorStateList.valueOf(0xff123456.toInt()); val font = Typeface.MONOSPACE
        icons[b] = tint; fonts.remove(b); b.typeface = font
        call("restoreCinemaDockIconTints", emptyArray()); assertSame(tint, TextViewCompat.getCompoundDrawableTintList(b)); assertSame(font, b.typeface)
        icons.remove(b); fonts[b] = Typeface.SERIF
        TextViewCompat.setCompoundDrawableTintList(b, tint); call("restoreCinemaDockIconTints", emptyArray())
        assertSame(tint, TextViewCompat.getCompoundDrawableTintList(b)); assertSame(Typeface.SERIF, b.typeface)
    }
    @Test fun recordingVisibilityUsesTheActiveEngineAndLiveStatus() {
        val actions = field("iptvRecordingActionsController")!!
        TvPlayerOriginalAccess.set(actions, "recordingEngineEnabled\$delegate", lazyOf(false))
        button("iptvRecordButton").text = "Stale"; button("iptvRecordButton").alpha = 0.2f
        presentation(channel()); assertEquals(View.GONE, button("iptvRecordButton").visibility)
        assertEquals("Record", button("iptvRecordButton").text.toString()); assertFalse(button("iptvRecordButton").isEnabled)
        assertFalse(button("iptvRecordButton").isFocusable); assertEquals(0.4f, button("iptvRecordButton").alpha, 0f)
        TvPlayerOriginalAccess.set(actions, "recordingEngineEnabled\$delegate", lazyOf(true))
        button("iptvRecordButton").text = "Stale"; button("iptvRecordButton").alpha = 0.2f
        presentation(channel()); assertEquals(View.VISIBLE, button("iptvRecordButton").visibility)
        assertEquals("Record", button("iptvRecordButton").text.toString()); assertTrue(button("iptvRecordButton").isEnabled)
        assertTrue(button("iptvRecordButton").isFocusable); assertEquals(1f, button("iptvRecordButton").alpha, 0f)
        presentation(channel(live = false)); assertEquals(View.GONE, button("iptvRecordButton").visibility)
    }
}
