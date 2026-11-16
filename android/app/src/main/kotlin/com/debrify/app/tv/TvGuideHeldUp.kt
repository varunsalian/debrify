package com.debrify.app.tv

import android.view.KeyEvent
import android.view.View
import androidx.recyclerview.widget.RecyclerView

/**
 * A held UP in a guide's channel list walks it one row per repeat (the list's
 * own focus search) and stops on the first row. Only a fresh press leaves the
 * list for the header above it, so holding UP to reach channel 1 never
 * overshoots into the source picker or search bar.
 *
 * Before this, three repeats of UP jumped straight to the search bar, so a
 * held UP could not scroll the list at all.
 */
internal object TvGuideHeldUp {
    /**
     * True when [event] is a repeated UP whose next focus target is outside
     * [list]: the caller consumes it and focus stays on the row it is on.
     */
    fun holdsInList(list: RecyclerView?, event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_DPAD_UP || event.repeatCount == 0) return false
        val focused = list?.findFocus() ?: return false
        // RecyclerView's own focus search lays out the row above when it is
        // off screen, so a null or outside target really means the top.
        val next = focused.focusSearch(View.FOCUS_UP) ?: return true
        return !isInside(list, next)
    }

    private fun isInside(list: View, view: View): Boolean {
        var current: View? = view
        while (current != null) {
            if (current === list) return true
            current = current.parent as? View
        }
        return false
    }
}
