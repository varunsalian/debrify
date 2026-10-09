package com.debrify.app.tv

import android.os.Looper
import android.os.Handler
import android.os.Message
import android.view.View
import java.lang.ref.WeakReference
import org.robolectric.util.ReflectionHelpers
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowChoreographer
import java.time.Duration

/** Pump paused vsync one millisecond at a time without advancing frame deadlines. */
internal object TvPlaylistUiQueue {
    private var root=WeakReference<View>(null)
    fun attach(view: View) { root=WeakReference(view) }
    private fun traversal() {
        val view=root.get() ?: return
        val impl=ReflectionHelpers.callInstanceMethod<Any?>(view,"getViewRootImpl") ?: return
        if(ReflectionHelpers.getField<Boolean>(impl,"mTraversalScheduled")) {
            // Use ViewRoot's own traversal entry point: it removes its barrier
            // and updates its scheduled/token state together.
            ReflectionHelpers.callInstanceMethod<Any?>(impl,"doTraversal")
        }
    }
    fun pauseFrames() {
        ShadowChoreographer.setFrameDelay(Duration.ofMillis(1))
        ShadowChoreographer.setPaused(true)
        // Reset Robolectric's shared vsync deadline for this activity/clock.
        ReflectionHelpers.callStaticMethod<Any?>(ShadowChoreographer::class.java,"setNextVsyncTimeNanos",
            ReflectionHelpers.ClassParameter.from(Long::class.javaPrimitiveType,android.os.SystemClock.elapsedRealtimeNanos()+1_000_000L))
    }
    fun pending(handler: Handler,action: Runnable): Boolean {
        var message=ReflectionHelpers.getField<Message?>(Looper.getMainLooper().queue,"mMessages")
        while(message!=null) {
            if(message.target===handler && message.callback===action)return true
            message=ReflectionHelpers.getField(message,"next")
        }
        return false
    }
    fun advance(ms: Long) {
        require(ms >= 0)
        traversal();shadowOf(Looper.getMainLooper()).idle()
        repeat(ms.toInt()) {
            traversal();shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(1));traversal()
        }
        traversal();shadowOf(Looper.getMainLooper()).idle()
    }
}
