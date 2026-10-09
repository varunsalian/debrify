package com.debrify.app.tv

import android.view.View
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.robolectric.util.ReflectionHelpers

/** Keep the actual framework-installed production callback before cancellation.
 * Deliberate late delivery exercises its liveness guard; no callback body is faked.
 */
internal object TvControlsEndActions {
    fun capture(view: View): Runnable {
        val animator = view.animate()
        val actions = ReflectionHelpers.getField<Map<Any, Runnable>?>(animator, "mAnimatorOnEndMap")
        val pending = ReflectionHelpers.getField<Runnable?>(animator, "mPendingOnEndAction")
        val action = actions?.values?.singleOrNull() ?: pending
        assertNotNull("production animation must install its end action", action)
        return action!!
    }
    fun curve(view: View, expected: android.animation.TimeInterpolator) {
        val actual = view.animate().interpolator
        assertNotNull("animation easing must be installed", actual)
        for (fraction in listOf(0.25f, 0.5f, 0.75f)) {
            assertEquals("easing at $fraction", expected.getInterpolation(fraction), actual!!.getInterpolation(fraction), 0.00001f)
        }
    }
}
