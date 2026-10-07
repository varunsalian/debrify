package com.debrify.app.tv

import android.os.Looper
import com.debrify.app.MainActivity
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.robolectric.Shadows.shadowOf
import java.time.Duration

internal open class TvFlutterRequestsOriginalTest : TvPhase2OriginalTest() {
    protected val messenger = TvPlayerRecordingMessenger()
    protected val function1Type = kotlin.jvm.functions.Function1::class.java
    protected val function2Type = kotlin.jvm.functions.Function2::class.java
    private var previous: MethodChannel? = null
    @Before fun installChannel() {
        previous = MainActivity.getAndroidTvPlayerChannel()
        reconnectChannel()
    }
    protected fun reconnectChannel() = MainActivity.setAndroidTvPlayerChannel(MethodChannel(messenger, "com.debrify.app/android_tv_player"))
    @After fun restoreChannel() {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(46))
        MainActivity.setAndroidTvPlayerChannel(previous)
    }
    protected fun idle() = shadowOf(Looper.getMainLooper()).idle()
    protected fun assertRequest(method: String, arguments: Map<String, Any?>) {
        val request = messenger.requests.last()
        assertEquals("com.debrify.app/android_tv_player", request.channel)
        assertEquals(method, request.call.method)
        assertEquals(arguments, request.call.arguments)
    }
    protected fun assertMainThread() = assertEquals(Looper.getMainLooper(), Looper.myLooper())
}
