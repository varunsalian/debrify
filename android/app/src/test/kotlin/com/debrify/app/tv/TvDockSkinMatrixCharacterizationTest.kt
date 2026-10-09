package com.debrify.app.tv

import android.content.res.ColorStateList
import android.graphics.Typeface
import android.os.Handler
import android.view.View
import android.widget.TextView
import androidx.core.widget.TextViewCompat
import androidx.media3.ui.AspectRatioFrameLayout
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.LooperMode

/** Every parameterized test owns a distinct activity; preferences are seeded before lazy reads. */
@RunWith(ParameterizedRobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvDockSkinMatrixCharacterizationTest(
    override val skin: TvControlsSkin,
    override val guide: GuideStyle,
) : TvPhase15OriginalTest() {
    companion object {
        @JvmStatic @ParameterizedRobolectricTestRunner.Parameters(name = "{0}-{1}")
        fun parameters(): List<Array<Any>> = TvControlsSkin.entries.flatMap { skin ->
            GuideStyle.entries.map { guide -> arrayOf<Any>(skin, guide) }
        }
    }
    private val installed get() = skin != TvControlsSkin.CLASSIC
    private fun label() = field("ottCaptionLabel") as TextView?
    private fun pending() = TvPlaylistUiQueue.pending(field("controlsHandler") as Handler, field("hideControlsRunnable") as Runnable)
    private fun controls(visible: Boolean) {
        set("controlsMenuVisible", visible)
        if (visible) pv().showController()
        (field("controlsOverlay") as View).visibility = if (visible) View.VISIBLE else View.GONE
        (field("controlsOverlay") as View).alpha = if (visible) 1f else 0f
        probe.playing = true
    }
    private fun styleButtons() = listOf("audioButton", "subtitleButton", "aspectButton", "pauseButton", "speedButton", "nightModeButton", "iptvPrevButton", "iptvNextButton", "iptvJumpButton", "iptvStartOverButton", "iptvStartOverSeekButton", "iptvRecordButton", "iptvGuideButton").mapNotNull { field(it) as? androidx.appcompat.widget.AppCompatButton }
    @Suppress("UNCHECKED_CAST") private fun originals() = field("originalControlDockOrder") as List<View>

    @Test fun constructionBindsTheSelectedLayoutAndEverySharedView() {
        view(R.id.debrify_controls_root)!!.visibility = View.VISIBLE
        view(R.id.debrify_controls_root)!!.alpha = 0.6f
        set("controlsOverlay", null)
        button("nightModeButton").text = "Rebind night"; button("aspectButton").text = "Rebind aspect"
        (field("iptvPrevButton") as? View)?.visibility = View.VISIBLE
        (field("cinemaProgressContainer") as View).onFocusChangeListener = null
        (field("seekbarHandler") as Handler).removeCallbacks(field("seekbarProgressRunnable") as Runnable)
        setup()
        assertNotNull("cinema progress callback installed", (field("cinemaProgressContainer") as View).onFocusChangeListener)
        assertTrue("seekbar ticker started", TvPlaylistUiQueue.pending(field("seekbarHandler") as Handler, field("seekbarProgressRunnable") as Runnable))
        assertEquals(installed, field("ottSkinInstalled"))
        assertEquals(skin, call("getControlsSkin", emptyArray()))
        assertEquals(guide, call("getGuideStyle", emptyArray()))
        val fields = mapOf("controlsOverlay" to R.id.debrify_controls_root, "pauseButton" to R.id.debrify_pause_button,
            "nightModeButton" to R.id.debrify_night_mode_button, "audioButton" to R.id.debrify_audio_button,
            "subtitleButton" to R.id.debrify_subtitle_button, "aspectButton" to R.id.debrify_aspect_button,
            "speedButton" to R.id.debrify_speed_button, "iptvGuideButton" to R.id.debrify_playlist_button,
            "iptvPrevButton" to R.id.debrify_prev_button, "iptvNextButton" to R.id.debrify_next_button,
            "iptvJumpButton" to R.id.iptv_jump_channel_button, "iptvStartOverButton" to R.id.iptv_start_over_button,
            "iptvStartOverSeekButton" to R.id.iptv_start_over_seek_button, "iptvRecordButton" to R.id.iptv_record_button,
            "debrifyTimeDisplay" to R.id.debrify_time_display, "debrifyTimeCurrent" to R.id.debrify_time_current,
            "debrifyTimeTotal" to R.id.debrify_time_total, "debrifyProgressLine" to R.id.debrify_progress_line,
            "cinemaProgressBuffered" to R.id.cinema_progress_buffered, "cinemaProgressContainer" to R.id.cinema_progress_container,
            "cinemaProgressBackground" to R.id.cinema_progress_background, "cinemaProgressThumb" to R.id.cinema_progress_thumb,
            "cinemaSpeedIndicator" to R.id.cinema_speed_indicator)
        fields.forEach { (name, id) -> assertSame("bound $name", view(id), field(name)) }
        assertNotNull(field("controlsOverlay")); assertNotNull(field("pauseButton"))
        assertEquals(View.GONE, (field("controlsOverlay") as View).visibility)
        assertEquals(0f, (field("controlsOverlay") as View).alpha, 0f)
        assertEquals(children(), originals())
        assertEquals("Fit", button("aspectButton").text.toString())
        assertEquals("Off", button("nightModeButton").text.toString())
        (field("iptvPrevButton") as? View)?.let { assertEquals("single VOD has no preceding episode", View.GONE, it.visibility) }
        if (installed) {
            val ottFields = mapOf("ottCaptionLabel" to R.id.ott_caption_label, "ottIdentityTitle" to R.id.ott_identity_title,
                "ottIdentitySubtitle" to R.id.ott_identity_subtitle, "ottIdentityOverline" to R.id.ott_identity_overline,
                "ottIdentityBadge" to R.id.ott_identity_badge, "ottIdentityDivider" to R.id.ott_identity_divider,
                "ottRatingChip" to R.id.ott_rating_chip, "ottMetaLine" to R.id.ott_meta_line,
                "ottScrubPreviewChip" to R.id.ott_scrub_preview_chip, "ottScrubPreviewText" to R.id.ott_scrub_preview_text,
                "ottProgressTrackContainer" to R.id.cinema_progress_track_container, "ottSourcesButton" to R.id.ott_sources_button)
            ottFields.forEach { (name, id) -> assertSame("OTT $name", view(id), field(name)) }
            val chips = field("ottQualityChips") as Array<*>
            listOf(R.id.ott_quality_1, R.id.ott_quality_2, R.id.ott_quality_3).forEachIndexed { i, id -> assertSame(view(id), chips[i]) }
            val idle = when (skin) { TvControlsSkin.MARQUEE -> 2; TvControlsSkin.BROADCAST, TvControlsSkin.PULSE -> 5; TvControlsSkin.TICKET -> 4; else -> 3 }
            assertEquals((idle * activity.resources.displayMetrics.density).toInt(), (field("ottProgressTrackContainer") as View).layoutParams.height)
        } else assertNull(label())
    }

    @Test fun focusAnimationCaptionAndTheClassicOverrideQuirkArePreserved() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(java.time.Duration.ofMillis(16))
        controls(true); layout()
        val pause = button("pauseButton")
        focus(pause, true)
        if (installed) assertEquals(120L, pause.animate().duration)
        advance(250)
        val scale = when (skin) { TvControlsSkin.MARQUEE, TvControlsSkin.TICKET, TvControlsSkin.CLASSIC -> 1f; TvControlsSkin.BROADCAST -> 1.06f; else -> 1.08f }
        val lift = when (skin) { TvControlsSkin.MARQUEE -> 2f; TvControlsSkin.TICKET -> 1.5f; else -> 0f } * activity.resources.displayMetrics.density
        assertEquals(scale, pause.scaleX, 0.001f); assertEquals(scale, pause.scaleY, 0.001f)
        assertEquals(-lift, pause.translationY, 0.001f)
        assertTrue("focused playing controls extend timeout", pending())
        if (installed) {
            assertSame(pause, field("ottCaptionOwner")); assertEquals(pause.text.toString(), label()!!.text.toString())
            assertEquals(1f, label()!!.alpha, 0.001f); assertEquals(120L, label()!!.animate().duration)
        }
        focus(pause, false); advance(250)
        assertEquals(1f, pause.scaleX, 0.001f); assertEquals(1f, pause.scaleY, 0.001f); assertEquals(0f, pause.translationY, 0.001f)
        if (installed) { assertNull(field("ottCaptionOwner")); assertEquals(0f, label()!!.alpha, 0.001f) }
        (field("iptvStartOverSeekButton") as? View)?.let { seek ->
            focus(seek, true); advance(250)
            assertEquals("OTT reapply intentionally omits Start Over Seek", 1f, seek.scaleX, 0f)
        }
        assertEquals(installed, button("iptvRecordButton").onFocusChangeListener != null)
    }

    @Test fun everyInstalledFocusListenerHonoursControlsVisibilityAndFocusLoss() {
        org.robolectric.shadows.ShadowChoreographer.setPaused(false)
        org.robolectric.shadows.ShadowChoreographer.setFrameDelay(java.time.Duration.ofMillis(16))
        val buttons = listOf("pauseButton", "nightModeButton", "audioButton", "subtitleButton", "aspectButton", "speedButton", "iptvGuideButton", "iptvPrevButton", "iptvNextButton", "iptvJumpButton", "iptvStartOverButton", "iptvStartOverSeekButton")
        val extra = if (installed) listOf("iptvRecordButton" to (field("iptvRecordButton") as? View),
            "ottSourcesButton" to (field("ottSourcesButton") as? View),
            "back" to view(R.id.ott_seek_back_button), "forward" to view(R.id.ott_seek_forward_button)) else emptyList()
        (buttons.map { it to (field(it) as? View) } + ("random" to view(R.id.debrify_random_button)) + extra).forEach { (name, candidate) ->
            val target = candidate ?: return@forEach
            call("cancelScheduledHideControlsMenu", emptyArray()); controls(false); focus(target, true)
            assertFalse("hidden $name", pending())
            controls(true); focus(target, false); assertFalse("blur $name", pending())
            focus(target, true); assertTrue("focus $name", pending())
            if (!installed) {
                advance(250)
                assertEquals("classic $name has no surviving scale animation", 1f, target.scaleX, 0f)
                assertEquals(1f, target.scaleY, 0f); assertEquals(0f, target.translationZ, 0f)
            } else if (name != "iptvStartOverSeekButton") {
                assertEquals("styled $name animation duration", 120L, target.animate().duration)
                advance(250)
                val scale = when (skin) { TvControlsSkin.MARQUEE, TvControlsSkin.TICKET -> 1f; TvControlsSkin.BROADCAST -> 1.06f; else -> 1.08f }
                val lift = when (skin) { TvControlsSkin.MARQUEE -> 2f; TvControlsSkin.TICKET -> 1.5f; else -> 0f } * activity.resources.displayMetrics.density
                assertEquals("styled $name scale", scale, target.scaleX, 0.001f)
                assertEquals(scale, target.scaleY, 0.001f); assertEquals(-lift, target.translationY, 0.001f)
                assertSame("styled $name caption owner", target, field("ottCaptionOwner"))
                focus(target, false); advance(250)
                assertEquals(1f, target.scaleX, 0.001f); assertEquals(0f, target.translationY, 0.001f)
                assertNull(field("ottCaptionOwner")); assertEquals(0f, label()!!.alpha, 0.001f)
            }
        }
    }

    @Test fun setupRetainsTheFirstCapturedDockOrderAndDoesNotReinflate() {
        val root = view(R.id.debrify_controls_root)
        val first = originals()
        dock().removeViewAt(0)
        setup()
        assertSame(root, view(R.id.debrify_controls_root))
        assertSame(first, originals())
        assertNotEquals(children(), first)
    }

    @Test fun liveToVodRestoresDockOrderVisibilityAndSeekState() {
        val first = originals()
        val previous = listOf("iptvPrevButton", "iptvNextButton").associateWith { (field(it) as? View)?.visibility }
        val live = channel(live = true); iptv(live)
        set("cinemaSeekMode", true); set("cinemaSeekWasPlaying", true)
        (field("cinemaProgressThumb") as View).visibility = View.VISIBLE
        (field("cinemaSpeedIndicator") as View).visibility = View.VISIBLE
        val removed = mutableListOf<View>(); val added = mutableListOf<View>()
        dock().setOnHierarchyChangeListener(object : android.view.ViewGroup.OnHierarchyChangeListener {
            override fun onChildViewRemoved(parent: View, child: View) { removed.add(child) }
            override fun onChildViewAdded(parent: View, child: View) { added.add(child) }
        })
        call("setupIptvControls", emptyArray())
        assertEquals("original detach callback order", first.asReversed(), removed)
        assertEquals("CH -", button("iptvPrevButton").text.toString()); assertEquals("CH +", button("iptvNextButton").text.toString())
        listOf("iptvGuideButton", "iptvJumpButton").forEach { (field(it) as? View)?.let { button -> assertEquals(View.VISIBLE, button.visibility) } }
        assertEquals(View.GONE, button("speedButton").visibility)
        assertEquals(false, field("cinemaSeekMode")); assertEquals(false, field("cinemaSeekWasPlaying"))
        assertEquals(View.INVISIBLE, (field("cinemaProgressThumb") as View).visibility)
        assertEquals(View.GONE, (field("cinemaSpeedIndicator") as View).visibility)
        val leading = listOfNotNull(field("audioButton"), field("subtitleButton"), field("aspectButton"), view(R.id.debrify_controls_left_divider),
            field("iptvPrevButton"), field("pauseButton"), field("iptvStartOverButton"), field("iptvStartOverSeekButton"), field("iptvNextButton"),
            view(R.id.debrify_controls_right_divider), field("iptvGuideButton"), field("iptvJumpButton"), field("iptvRecordButton"), field("nightModeButton"))
        assertEquals(leading + first.filterNot { it in leading }, children())
        assertEquals(children(), added); removed.clear(); added.clear()
        val liveOrder = children()
        presentation(channel(live = false))
        assertEquals("VOD detach callback order", liveOrder.asReversed(), removed); assertEquals(first, added)
        assertEquals(R.drawable.cinema_dock_bg, org.robolectric.Shadows.shadowOf(dock().background).createdFromResId)
        styleButtons().forEach { b ->
            val play = b === button("pauseButton")
            assertEquals(if (play) R.drawable.cinema_play_button_bg else R.drawable.cinema_button_bg,
                org.robolectric.Shadows.shadowOf(b.background).createdFromResId)
            colorStates(androidx.core.content.ContextCompat.getColorStateList(activity,
                if (play) R.color.cinema_play_button_text else R.color.cinema_control_button_text)!!, b.textColors)
        }
        assertEquals(first, children())
        listOf("iptvGuideButton", "iptvJumpButton", "iptvRecordButton").forEach { (field(it) as? View)?.let { button -> assertEquals(View.GONE, button.visibility) } }
        previous.forEach { (name, value) -> assertEquals("live to VOD leaves channel buttons as-is", value, (field(name) as? View)?.visibility) }
        assertEquals(View.VISIBLE, button("speedButton").visibility)
        assertEquals(View.VISIBLE, (field("cinemaProgressContainer") as View).visibility)
    }

    private fun colorStates(expected: ColorStateList, actual: ColorStateList) {
        listOf(intArrayOf(android.R.attr.state_enabled), intArrayOf(android.R.attr.state_enabled, android.R.attr.state_focused),
            intArrayOf(android.R.attr.state_enabled, android.R.attr.state_pressed), intArrayOf(-android.R.attr.state_enabled)).forEach { state ->
            assertEquals(expected.getColorForState(state, expected.defaultColor), actual.getColorForState(state, actual.defaultColor))
        }
    }
    @Test fun styledLiveSkinCapturesIconTintAndTypefaceOnceAndRestoresThem() {
        val buttons = styleButtons()
        val originalTint = ColorStateList.valueOf(0xff345678.toInt())
        val originalFont = Typeface.create("serif", Typeface.BOLD)
        buttons.forEach { TextViewCompat.setCompoundDrawableTintList(it, originalTint); it.typeface = originalFont }
        val tokens = GuideTokens.of(guide)
        if (tokens?.monoFont != null) {
            @Suppress("UNCHECKED_CAST") val fonts = field("guideTypefaces") as MutableMap<String, Typeface?>
            fonts[tokens.monoFont!!] = Typeface.MONOSPACE
        }
        iptv(channel(live = true)); call("setupIptvControls", emptyArray())
        val tints = field("cinemaIconTints") as Map<*, *>
        val fonts = field("cinemaButtonTypefaces") as Map<*, *>
        if (tokens == null) {
            assertTrue(tints.isEmpty()); assertTrue(fonts.isEmpty())
            assertEquals(R.drawable.iptv_premium_panel_bg, org.robolectric.Shadows.shadowOf(dock().background).createdFromResId)
            val colors = androidx.core.content.ContextCompat.getColorStateList(activity, R.color.iptv_premium_button_text)!!
            buttons.forEach { button ->
                assertEquals(R.drawable.iptv_premium_button_bg, org.robolectric.Shadows.shadowOf(button.background).createdFromResId)
                colorStates(colors, button.textColors)
            }
        } else {
            assertEquals(buttons.toSet(), tints.keys); assertEquals(buttons.toSet(), fonts.keys)
            buttons.forEach { assertSame(originalTint, tints[it]); assertSame(originalFont, fonts[it]) }
            val density = activity.resources.displayMetrics.density
            val panelRadius = when (guide) { GuideStyle.GLASS -> 22; GuideStyle.EDITION -> 8; else -> 4 }
            val buttonRadius = when (guide) { GuideStyle.GLASS -> 16; GuideStyle.EDITION -> 6; else -> 3 }
            assertTrue("styled dock panel", dock().background is android.graphics.drawable.GradientDrawable)
            val panel = dock().background as android.graphics.drawable.GradientDrawable
            assertEquals((panelRadius * density).toInt().toFloat(), panel.cornerRadius, 0f)
            assertEquals(tokens.panel, panel.color!!.defaultColor)
            val state: Any = org.robolectric.util.ReflectionHelpers.getField(panel, "mGradientState")
            assertEquals((density).toInt(), org.robolectric.util.ReflectionHelpers.getField<Int>(state, "mStrokeWidth"))
            assertEquals(tokens.hairline2, org.robolectric.util.ReflectionHelpers.getField<ColorStateList>(state, "mStrokeColors").defaultColor)
            buttons.forEach { button ->
                assertTrue("styled button shape", button.background.current is android.graphics.drawable.GradientDrawable)
                assertEquals((buttonRadius * density).toInt().toFloat(), (button.background.current as android.graphics.drawable.GradientDrawable).cornerRadius, 0f)
            }
            val expected = tokens.buttonTextColors()
            buttons.forEach { colorStates(expected, it.textColors); colorStates(expected, TextViewCompat.getCompoundDrawableTintList(it)!!) }
            if (guide == GuideStyle.CONSOLE) buttons.forEach { assertSame(Typeface.MONOSPACE, it.typeface) }
            presentation(channel(live = true))
            buttons.forEach { assertSame(originalTint, tints[it]); assertSame(originalFont, fonts[it]) }
            presentation(channel(live = false))
            buttons.forEach { assertSame(originalTint, TextViewCompat.getCompoundDrawableTintList(it)); assertSame(originalFont, it.typeface) }
        }
    }
    @Test fun vodToLiveRestylesOnlyTheNonClassicGuideSkin() {
        iptv(channel()); call("setupIptvControls", emptyArray())
        presentation(channel(live = false))
        assertEquals(R.drawable.cinema_dock_bg, org.robolectric.Shadows.shadowOf(dock().background).createdFromResId)
        presentation(channel())
        val tokens = GuideTokens.of(guide)
        if (tokens == null) {
            assertEquals("classic retains its restored cinema background on the return trip", R.drawable.cinema_dock_bg,
                org.robolectric.Shadows.shadowOf(dock().background).createdFromResId)
        } else {
            assertTrue("styled panel is reapplied", dock().background is android.graphics.drawable.GradientDrawable)
            assertEquals(tokens.panel, (dock().background as android.graphics.drawable.GradientDrawable).color!!.defaultColor)
            styleButtons().forEach { colorStates(tokens.buttonTextColors(), it.textColors) }
        }
    }
}
