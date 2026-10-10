package com.debrify.app.tv

import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.RealObject
import org.robolectric.shadow.api.Shadow
import org.robolectric.util.ReflectionHelpers.ClassParameter

/** Callback order observers delegate to the real diagnostics/gate implementations. */
internal object TvPhase19CallbackTrace { val events = mutableListOf<String>(); var onManual: (() -> Unit)? = null }
@Implements(IptvTuneDiagnostics::class, isInAndroidSdk = false)
internal class TvPhase19DiagnosticsShadow {
    @RealObject private lateinit var target: IptvTuneDiagnostics
    @Implementation fun onFirstFrame() {
        TvPhase19CallbackTrace.events.add("diagnostic")
        Shadow.directlyOn<Unit>(target, "com.debrify.app.tv.IptvTuneDiagnostics", "onFirstFrame")
    }
    @Implementation fun onBytesLoaded(bytes: Long) {
        Shadow.directlyOn<Unit>(target, "com.debrify.app.tv.IptvTuneDiagnostics", "onBytesLoaded", ClassParameter.from(Long::class.javaPrimitiveType, bytes))
    }
}
@Implements(TvStartupGateController::class, isInAndroidSdk = false)
internal class TvPhase19GateShadow {
    @RealObject private lateinit var target: TvStartupGateController
    @Implementation(methodName = "mediaServerPlaybackLog\$app_debug")
    fun mediaServerPlaybackLog(event: String, errorCode: Int?, httpStatus: Int?) {
        TvPhase19CallbackTrace.events.add("server:$event")
        Shadow.directlyOn<Unit>(target, "com.debrify.app.tv.TvStartupGateController", "mediaServerPlaybackLog\$app_debug",
            ClassParameter.from(String::class.java, event), ClassParameter.from(Int::class.javaObjectType, errorCode),
            ClassParameter.from(Int::class.javaObjectType, httpStatus))
    }
    @Implementation fun commitManualSourceCandidate() {
        TvPhase19CallbackTrace.onManual?.invoke()
        TvPhase19CallbackTrace.events.add("manual commit")
        Shadow.directlyOn<Unit>(target, "com.debrify.app.tv.TvStartupGateController", "commitManualSourceCandidate")
    }
    @Implementation fun commitStartupCandidate() {
        TvPhase19CallbackTrace.events.add("startup commit")
        Shadow.directlyOn<Unit>(target, "com.debrify.app.tv.TvStartupGateController", "commitStartupCandidate")
    }
}
