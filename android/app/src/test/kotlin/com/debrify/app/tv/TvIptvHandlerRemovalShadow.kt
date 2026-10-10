package com.debrify.app.tv

import android.os.Handler
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.RealObject
import org.robolectric.annotation.Resetter
import org.robolectric.shadow.api.Shadow
import org.robolectric.util.ReflectionHelpers.ClassParameter

/** Observe exact Runnable cancellation, then execute Android's unchanged implementation. */
@Implements(Handler::class)
internal class TvIptvHandlerRemovalShadow {
    @RealObject private lateinit var handler: Handler
    @Implementation protected fun removeCallbacks(action: Runnable) {
        observe?.invoke(handler,action)
        Shadow.directlyOn<Unit>(handler,"android.os.Handler","removeCallbacks",ClassParameter.from(Runnable::class.java,action))
    }
    companion object {
        var observe: ((Handler,Runnable) -> Unit)? = null
        @JvmStatic @Resetter fun reset() {observe=null}
    }
}
