package com.debrify.app.storage

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver
import org.robolectric.shadows.ShadowLooper
import java.nio.ByteBuffer

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class LocalSourceAccessTest {
    @Test fun `picker persists read permission and a new bridge can read the same document`() {
        val lifecycle = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = lifecycle.get()
        val provider = LocalSourceDocumentReaderTest.TestProvider()
        provider.documents["movie:one"] = arrayOf("movie:one", "Movie.mkv", "video/x-matroska", 100L, 200L)
        ShadowContentResolver.registerProviderInternal("local.test", provider)
        val messenger = Messenger()
        val bridge = LocalSourceAccess(activity, messenger)
        var picked: Any? = null
        messenger.call("pickFile") { picked = it }
        val request = shadowOf(activity).nextStartedActivityForResult
        assertEquals(Intent.ACTION_OPEN_DOCUMENT, request.intent.action)
        assertTrue(request.intent.flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0)
        val uri = Uri.parse("content://local.test/document/movie%3Aone")
        bridge.onActivityResult(request.requestCode, Activity.RESULT_OK, Intent().setData(uri))
        await { picked != null }
        val permission = activity.contentResolver.persistedUriPermissions.single { it.uri == uri }
        assertTrue(permission.isReadPermission)
        assertFalse(permission.isWritePermission)
        bridge.dispose()

        val reopened = LocalSourceAccess(activity, messenger)
        var stat: Any? = null
        messenger.call("stat", mapOf("uri" to uri.toString())) { stat = it }
        await { stat != null }
        assertEquals("Movie.mkv", (stat as Map<*, *>)["name"])
        reopened.dispose()
        lifecycle.pause().stop().destroy()
    }

    @Test fun `cancelled folder picker returns null and persists nothing`() {
        val lifecycle = Robolectric.buildActivity(Activity::class.java).setup()
        val activity = lifecycle.get()
        val messenger = Messenger()
        val bridge = LocalSourceAccess(activity, messenger)
        var completed = false
        messenger.call("pickDirectory") { assertNull(it); completed = true }
        val request = shadowOf(activity).nextStartedActivityForResult
        assertEquals(Intent.ACTION_OPEN_DOCUMENT_TREE, request.intent.action)
        bridge.onActivityResult(request.requestCode, Activity.RESULT_CANCELED, null)
        assertTrue(completed)
        assertTrue(activity.contentResolver.persistedUriPermissions.isEmpty())
        bridge.dispose()
        lifecycle.pause().stop().destroy()
    }

    private fun await(done: () -> Boolean) {
        val deadline = System.nanoTime() + 3_000_000_000L
        while (!done() && System.nanoTime() < deadline) {
            ShadowLooper.idleMainLooper()
            Thread.sleep(5)
        }
        assertTrue("Native operation did not finish", done())
    }

    private class Messenger : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null
        override fun send(channel: String, message: ByteBuffer?) {}
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {}
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) { this.handler = handler }
        fun call(method: String, arguments: Any? = null, reply: (Any?) -> Unit) {
            val message = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments))
            message.flip()
            handler!!.onMessage(message) { response ->
                response!!.flip()
                reply(StandardMethodCodec.INSTANCE.decodeEnvelope(response))
            }
        }
    }
}
