package com.debrify.app.tv

import android.view.ViewPropertyAnimator
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.RealObject
import org.robolectric.shadow.api.Shadow

/** Records cancellation while retaining the framework animation implementation. */
@Implements(ViewPropertyAnimator::class)
internal class TvPhase15AnimatorShadow {
    @RealObject private lateinit var animator: ViewPropertyAnimator
    @Implementation fun cancel() {
        cancelled.add(animator)
        Shadow.directlyOn<Unit>(animator, "android.view.ViewPropertyAnimator", "cancel")
    }
    companion object {
        val cancelled = mutableListOf<ViewPropertyAnimator>()
    }
}
