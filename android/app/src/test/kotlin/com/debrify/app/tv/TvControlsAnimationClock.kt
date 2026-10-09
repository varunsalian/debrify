package com.debrify.app.tv

import android.animation.ValueAnimator
import android.os.SystemClock
import org.robolectric.util.ReflectionHelpers

/** Dispatch actual framework callbacks at the paused main-looper clock.
 * Bootstrap can leave native vsync stalled; no animator, listener, interpolator,
 * duration or end action is replaced. Handler deadlines still use the real queue.
 */
internal object TvControlsAnimationClock {
    private val handlerType = Class.forName("android.animation.AnimationHandler")
    private val frame = Class.forName("android.animation.AnimationHandler\$AnimationFrameCallback").getDeclaredMethod("doAnimationFrame", Long::class.javaPrimitiveType)
        .apply { isAccessible = true }
    fun dispatch(animator: ValueAnimator) { frame.invoke(animator, SystemClock.uptimeMillis()) }
    private fun dispatchAll() {
        val handler = handlerType.getDeclaredMethod("getInstance").apply { isAccessible = true }.invoke(null)
        val callbacks = ReflectionHelpers.getField<List<Any?>>(handler, "mAnimationCallbacks").toList()
        callbacks.filterNotNull().forEach { frame.invoke(it, SystemClock.uptimeMillis()) }
    }
    fun advance(ms: Long) {
        require(ms >= 0)
        TvPlaylistUiQueue.advance(0); dispatchAll()
        repeat(ms.toInt()) { TvPlaylistUiQueue.advance(1); dispatchAll() }
    }
}
