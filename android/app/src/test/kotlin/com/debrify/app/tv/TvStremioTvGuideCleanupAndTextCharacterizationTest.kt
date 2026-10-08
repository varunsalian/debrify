package com.debrify.app.tv

import android.os.Handler
import android.view.KeyEvent
import android.view.View
import android.widget.ImageView
import androidx.media3.common.Player
import com.bumptech.glide.request.target.DrawableImageViewTarget
import com.debrify.app.R
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowChoreographer

/** Active waits and lowercase names exercise the cleanup and fallback boundaries. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@LooperMode(LooperMode.Mode.PAUSED)
@androidx.annotation.OptIn(androidx.media3.common.util.UnstableApi::class)
internal class TvStremioTvGuideCleanupAndTextCharacterizationTest : TvPhase7OriginalTest() {
    private fun waitForReady() {
        standard(); set("stremioTvGuideVisible", true); invoke("hideGuideWhenReady")
    }

    private fun assertWaitRemoved(listener: Any?) {
        assertEquals("hide removes the current player's ready listener", listOf(listener), probe.removed)
        assertTrue("no ready listener remains on the player", probe.listeners.isEmpty())
        assertNull("ready listener reference cleared", field("guidePanelReadyListener"))
        assertNull("timeout reference cleared", field("guidePanelTimeoutRunnable"))
        set("stremioTvGuideVisible", true)
        tick(10_000)
        assertTrue("removed timeout cannot hide a subsequently visible guide", visible())
    }

    @Test fun hideCancelsCurrentListenerAndPendingTimeout() {
        waitForReady(); val listener = field("guidePanelReadyListener")
        invoke("hideStremioTvGuide")
        assertFalse(visible()); assertWaitRemoved(listener)
    }

    @Test fun toggleAndBackHideCancelPendingGuideWait() {
        for (back in listOf(false, true)) {
            waitForReady(); probe.removed.clear(); val listener = field("guidePanelReadyListener")
            if (back) assertTrue(activity.dispatchKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_BACK)))
            else invoke("toggleStremioTvGuide")
            assertFalse("production close route hides guide", visible())
            assertWaitRemoved(listener)
        }
    }

    @Test fun cancelWithoutCurrentPlayerIsIdempotentAndPreservesOtherCallbacks() {
        waitForReady(); val listener = field("guidePanelReadyListener")
        var otherFired = false
        (field("progressHandler") as Handler).postDelayed({ otherFired = true }, 10_000)
        set("player", null)
        invoke("cancelGuideWait"); invoke("cancelGuideWait")
        assertNull("listener cleared even when current player is absent", field("guidePanelReadyListener"))
        assertNull("timeout cleared even when current player is absent", field("guidePanelTimeoutRunnable"))
        assertTrue("old player's listener is retained as-is", probe.listeners.contains(listener))
        tick(10_000)
        assertTrue("borrowed handler's unrelated callback still runs", otherFired)
        assertTrue("cancel removes only the guide's timeout", visible())
    }

    @Test fun replacementWaitRemovesOldDeadlineAndKeepsNewDeadline() {
        waitForReady(); val oldListener = field("guidePanelReadyListener")
        tick(500); invoke("hideGuideWhenReady")
        assertEquals("replacement unregisters old listener", listOf(oldListener), probe.removed)
        tick(9500)
        assertTrue("original deadline was cancelled", visible())
        assertEquals(1, probe.listeners.size)
        tick(499); assertTrue("replacement has its own full ten seconds", visible())
        tick(1); assertFalse("replacement deadline still hides guide", visible())
        assertTrue(probe.listeners.isEmpty())
    }

    @Test fun readyWhileAlreadyHiddenStillCleansListenerAndTimeout() {
        waitForReady(); val listener = field("guidePanelReadyListener")
        set("stremioTvGuideVisible", false)
        probe.emit(Player.STATE_READY)
        assertFalse(visible()); assertWaitRemoved(listener)
    }

    @Test fun timeoutWhileAlreadyHiddenStillCleansListenerAndReferences() {
        waitForReady(); val listener = field("guidePanelReadyListener")
        set("stremioTvGuideVisible", false); tick(10_000)
        assertFalse(visible())
        assertEquals("timeout cleanup runs even without another hide call", listOf(listener), probe.removed)
        assertTrue(probe.listeners.isEmpty())
        assertNull(field("guidePanelReadyListener")); assertNull(field("guidePanelTimeoutRunnable"))
    }

    @Test fun idleRemovesTimeoutWhileKeepingGuideVisible() {
        waitForReady(); val listener = field("guidePanelReadyListener")
        channels().forEach { it.isSwitchingChannel = true }
        probe.emit(Player.STATE_IDLE)
        assertTrue(visible()); assertWaitRemoved(listener)
        assertTrue("IDLE still clears all switching marks", channels().none { it.isSwitchingChannel })
    }

    @Test fun showCancelsPendingHideCompletion() {
        standard(); invoke("showStremioTvGuide")
        invoke("hideStremioTvGuide")
        val hideAnimation = overlayAnimation()
        hideAnimation.currentPlayTime = 30
        assertTrue("hide animation is pending before reopen", hideAnimation.isStarted)
        guide().animate().translationY(37f).setDuration(1000).start()
        val translation = overlayAnimation(hideAnimation)
        translation.currentPlayTime = 30
        assertTrue("another overlay property is animating before reopen", translation.isStarted)
        invoke("showStremioTvGuide")
        assertFalse("show cancels the pending hide animation", hideAnimation.isStarted)
        assertFalse("show cancels all overlay properties, including translation", translation.isStarted)
        ShadowChoreographer.setPaused(false); tick(300)
        assertTrue(visible())
        assertEquals("cancelled hide end action cannot make reopened guide GONE", View.VISIBLE, guide().visibility)
        assertEquals(1f, guide().alpha, 0.001f)
        ShadowChoreographer.setPaused(true)
    }

    @Test fun hideCancelsRunningOverlayAnimation() {
        standard(); guide().visibility = View.VISIBLE
        var cancelled = false
        guide().animate().translationY(37f).setDuration(1000).setListener(object : android.animation.AnimatorListenerAdapter() {
            override fun onAnimationCancel(animation: android.animation.Animator) { cancelled = true }
        }).start()
        val animation = overlayAnimation()
        animation.currentPlayTime = 30
        assertTrue("overlay animation is running before hide", animation.isStarted)
        invoke("hideStremioTvGuide")
        assertTrue("hide cancels the running overlay animation", cancelled)
        assertFalse(animation.isStarted)
        ShadowChoreographer.setPaused(false)
        tick(1200)
        assertTrue("cancelled translation does not reach its previous target", guide().translationY < 37f)
        assertEquals(View.GONE, guide().visibility)
        guide().animate().setListener(null)
        ShadowChoreographer.setPaused(true)
    }

    private fun overlayAnimation(excluding: android.animation.ValueAnimator? = null): android.animation.ValueAnimator {
        val animator = guide().animate()
        val animations = animator.javaClass.getDeclaredField("mAnimatorMap").apply { isAccessible = true }.get(animator) as Map<*, *>
        val selected = animations.keys.filter { it !== excluding }
        assertEquals("one selected platform overlay animation is pending", 1, selected.size)
        return selected.single() as android.animation.ValueAnimator
    }

    @Test fun absentPosterUppercasesLowercaseHeaderInitial() {
        init(json("0", "cinema")); invoke("updateStremioTvGuideHeader")
        assertEquals("channel name keeps its original casing", "cinema", text("stremioTvGuideCurrentName").text.toString())
        assertEquals("fallback header initial is uppercased", "C", text("stremioTvGuideNowLetter").text.toString())
        assertEquals(View.VISIBLE, view("stremioTvGuideNowLetter").visibility)
        assertEquals(View.GONE, view("stremioTvGuideNowPoster").visibility)
    }

    @Test fun failedPosterUppercasesLowercaseHeaderInitial() {
        init(json("0", "cinema")); channels()[0].nowPlayingPoster = "android.resource://com.debrify.app/${R.drawable.splash_logo}"
        invoke("updateStremioTvGuideHeader")
        val poster = view("stremioTvGuideNowPoster") as ImageView
        assertTrue(TvPlayerOriginalAccess.artworkListener(poster).onLoadFailed(null, "local", DrawableImageViewTarget(poster), true))
        assertEquals("failed poster uses uppercased fallback initial", "C", text("stremioTvGuideNowLetter").text.toString())
        assertEquals(View.VISIBLE, view("stremioTvGuideNowLetter").visibility)
        assertEquals(View.GONE, poster.visibility)
    }

    @Test fun rowUppercasesLowercaseInitialAndMixedCaseType() {
        init(json("0", "cinema").put("type", "mOvIe"))
        val row = adapter().onCreateViewHolder(list(), 0)
        adapter().onBindViewHolder(row, 0)
        assertEquals("row keeps channel name casing", "cinema", (row.itemView.findViewById<View>(R.id.stremio_tv_guide_channel_name) as android.widget.TextView).text.toString())
        assertEquals("row uppercases the fallback initial", "C", (row.itemView.findViewById<View>(R.id.stremio_tv_guide_poster_letter) as android.widget.TextView).text.toString())
        assertEquals("row uppercases the full type", "MOVIE", (row.itemView.findViewById<View>(R.id.stremio_tv_guide_type_badge) as android.widget.TextView).text.toString())
    }
}
