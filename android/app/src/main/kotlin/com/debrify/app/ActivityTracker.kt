package com.debrify.app

import android.app.Activity
import java.lang.ref.WeakReference

/**
 * Singleton that tracks the currently active (foreground) Activity.
 * Used by remote control to dispatch key events to the correct activity.
 */
object ActivityTracker {
    private var currentActivityRef: WeakReference<Activity>? = null

    /**
     * The currently active activity, or null if none.
     * Uses WeakReference to avoid memory leaks.
     */
    var currentActivity: Activity?
        get() = currentActivityRef?.get()
        set(value) {
            currentActivityRef = value?.let { WeakReference(it) }
        }
}
