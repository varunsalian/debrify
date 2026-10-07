package com.debrify.app.tv

import android.content.Context
import android.view.View
import android.widget.Button
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import java.lang.reflect.Proxy

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
internal class TvSkipPresentationCharacterizationTest : TvPhase3OriginalTest() {
    private val intro = TvSkipSegment(TvSkipSegmentType.INTRO, 1000, 20_000)
    private fun present(segment: TvSkipSegment? = intro, key: String? = "request") =
        call("presentSkipSegment", arrayOf(TvSkipSegment::class.java, String::class.java), segment, key)
    private fun button() = field("skipSegmentButton") as Button
    private fun setup() { lifecycle.create().start().resume().visible(); bindViews(); series(); button().isFocusableInTouchMode = true; (field("playerView") as View).isFocusableInTouchMode = true }

    @Test fun fadeInPinsDurationAndAlphaAndBothSegmentLabels() {
        setup(); present()
        assertEquals("Skip intro »", button().text.toString())
        assertEquals(0f, button().alpha, 0f); assertEquals(160L, button().animate().duration)
        advance(250); assertEquals(1f, button().alpha, 0.001f)
        present(TvSkipSegment(TvSkipSegmentType.OUTRO, 500_000, 600_000))
        assertEquals("Skip credits »", button().text.toString())
    }

    @Test fun controlsLiftAndReturnPinDensityScaledTargetAndDuration() {
        setup(); button().visibility = View.VISIBLE; set("controlsMenuVisible", true)
        present(); assertEquals(180L, button().animate().duration)
        advance(250)
        assertEquals(-128f * activity.resources.displayMetrics.density, button().translationY, 0.001f)
        set("controlsMenuVisible", false); present(); assertEquals(180L, button().animate().duration)
        advance(250); assertEquals(0f, button().translationY, 0.001f)
    }

    @Test fun translationDeadbandIncludesHalfPixelAndAnimatesJustBeyondIt() {
        setup(); button().visibility = View.VISIBLE
        for (offset in listOf(-0.5f, 0.5f, -0.501f, 0.501f)) {
            button().animate().cancel(); button().animate().duration = 777L
            button().translationY = offset; present()
            assertEquals("offset=$offset", if (kotlin.math.abs(offset) <= 0.5f) 777L else 180L, button().animate().duration)
        }
    }

    private class FocusPlayer(context: Context) : androidx.media3.ui.PlayerView(context) {
        val requests = mutableListOf<Int>()
        var skipButton: View? = null
        override fun requestFocus(direction: Int, previous: android.graphics.Rect?): Boolean {
            requests.add(skipButton?.visibility ?: -1); return super.requestFocus(direction, previous)
        }
    }
    @Test fun missingSegmentOrRequestRestoresPlayerFocusAndResetsPresentation() {
        setup(); val old = field("playerView") as View; val parent = old.parent as android.view.ViewGroup
        parent.removeView(old); val player = FocusPlayer(activity).apply { isFocusableInTouchMode = true }
        parent.addView(player); set("playerView", player); player.skipButton = button()
        button().visibility = View.VISIBLE; button().alpha = 1f; button().translationY = -20f
        button().requestFocus(); org.robolectric.Shadows.shadowOf(activity).setCurrentFocus(button()); assertTrue(button().hasFocus()); player.requests.clear()
        present(null); assertEquals(View.GONE, button().visibility)
        assertEquals(0f, button().alpha, 0f); assertEquals(0f, button().translationY, 0f)
        assertEquals("explicit handoff happens before hiding", View.VISIBLE, player.requests.first())
        button().visibility = View.VISIBLE; present(intro, null); assertEquals(View.GONE, button().visibility)
    }

    @Test fun skipFeedbackPinsSecondsSuffixFloorAndOneSecondMinimum() {
        setup(); val root = android.widget.FrameLayout(activity)
        val text = android.widget.TextView(activity).apply { id = com.debrify.app.R.id.seek_feedback_right_text }
        root.addView(text); set("seekFeedbackManager", SeekFeedbackManager(root))
        val p = PlayerProbe(position = 5000, duration = 600_000); set("player", p.player)
        for ((end, expected) in listOf(5500L to "+1s", 7999L to "+2s")) {
            p.position = 5000; set("activeSkipSegment", TvSkipSegment(TvSkipSegmentType.INTRO, 1000, end))
            invoke("skipActiveSegment"); assertEquals(expected, text.text.toString())
        }
    }

    private fun blocked(flag: String) {
        setup(); set(flag, true); present()
        assertNull("focus blocked by $flag", field("skipFocusOfferedKey"))
        set(flag, false); present(); assertEquals("request:INTRO:1000", field("skipFocusOfferedKey"))
    }
    @Test fun controlsMenuBlocksFocusOffer() = blocked("controlsMenuVisible")
    @Test fun playlistBlocksFocusOffer() = blocked("playlistVisible")
    @Test fun seekbarBlocksFocusOffer() = blocked("seekbarVisible")
    @Test fun actualUpNextCardBlocksPresentFocusOfferWithoutHidingTheSegment() {
        setup(); invoke("showUpNextCard", 1); present()
        assertEquals(View.VISIBLE, button().visibility); assertNull(field("skipFocusOfferedKey"))
        invoke("dismissUpNext"); present(); assertEquals("request:INTRO:1000", field("skipFocusOfferedKey"))
    }

    // Real overlay instances and their real isVisible getters. Only view and
    // callback constructor inputs are inert; no production focus policy is faked.
    private fun overlay(name: String) {
        setup()
        val type = AndroidTvTorrentPlayerActivity::class.java.getDeclaredField(name).type
        val ctor = type.constructors.filter { c -> c.parameterTypes.none { it.name.endsWith("DefaultConstructorMarker") } }.minBy { it.parameterCount }
        val position: () -> Long = { 0L }; val applied: (Long) -> Unit = { }
        val args = ctor.parameterTypes.map { t -> when {
            Context::class.java.isAssignableFrom(t) -> activity
            t == android.view.ViewGroup::class.java || t == View::class.java -> android.widget.FrameLayout(activity).apply {
                addView(View(activity).apply { id = com.debrify.app.R.id.unified_scrim })
                addView(View(activity).apply { id = com.debrify.app.R.id.unified_panel })
            }
            View::class.java.isAssignableFrom(t) -> t.getConstructor(Context::class.java).newInstance(activity)
            t == Runnable::class.java -> Runnable { }
            t.name == "kotlin.jvm.functions.Function0" -> position
            t.name == "kotlin.jvm.functions.Function1" -> applied
            t == List::class.java -> emptyList<String>()
            else -> Proxy.newProxyInstance(t.classLoader, arrayOf(t)) { _, m, _ -> when (m.returnType) {
                java.lang.Boolean.TYPE -> false
                java.lang.Integer.TYPE -> 0
                List::class.java -> emptyList<Any>()
                else -> null
            } }
        } }.toTypedArray()
        val panel = ctor.newInstance(*args); set(name, panel)
        TvPlayerOriginalAccess.set(panel, "isVisible", true); present()
        assertNull("focus blocked by $name", field("skipFocusOfferedKey"))
        TvPlayerOriginalAccess.set(panel, "isVisible", false); present()
        assertEquals("request:INTRO:1000", field("skipFocusOfferedKey"))
    }
    @Test fun subtitlePanelBlocksFocusOffer() = overlay("subtitlePanel")
    @Test fun unifiedMenuBlocksFocusOffer() = overlay("unifiedMenu")
    @Test fun sourceBrowserBlocksFocusOffer() = overlay("sourceBrowser")
    @Test fun syncOverlayBlocksFocusOffer() = overlay("syncOverlay")
    @Test fun linePickerBlocksFocusOffer() = overlay("linePickerOverlay")

    private class FocusButton(context: Context) : androidx.appcompat.widget.AppCompatButton(context) {
        var requests = 0
        override fun requestFocus(direction: Int, previous: android.graphics.Rect?): Boolean {
            requests++; return super.requestFocus(direction, previous)
        }
    }
    @Test fun focusOfferIsOncePerKeyAndPostedRequestRequiresVisibleButton() {
        setup(); val old = button(); val parent = old.parent as android.view.ViewGroup
        parent.removeView(old)
        val probe = FocusButton(activity).apply { visibility = View.GONE; isFocusableInTouchMode = true }
        parent.addView(probe); set("skipSegmentButton", probe)
        present(); idle(); assertEquals(1, probe.requests)
        (field("playerView") as View).requestFocus(); present(); idle(); assertEquals(1, probe.requests)
        present(key = "different"); probe.visibility = View.GONE; idle(); assertEquals(1, probe.requests)
    }
}
