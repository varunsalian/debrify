package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer

/** The buffers and reply thread match Flutter's binary MethodChannel contract. */
internal class TvPlayerRecordingMessenger : BinaryMessenger {
    data class Request(val channel: String, val call: MethodCall, val reply: BinaryMessenger.BinaryReply?)
    val requests = mutableListOf<Request>()
    var throwOnSend = false
    private val codec = StandardMethodCodec.INSTANCE
    private val main = Handler(Looper.getMainLooper())

    override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)
    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        if (throwOnSend) throw IllegalStateException("messenger unavailable")
        val readable = message!!.duplicate().apply { flip() }
        requests.add(Request(channel, codec.decodeMethodCall(readable), callback))
    }
    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit

    fun success(value: Any?, index: Int = requests.lastIndex) = post(index, codec.encodeSuccessEnvelope(value))
    fun error(index: Int = requests.lastIndex) = post(index, codec.encodeErrorEnvelope("error", "message", mapOf("detail" to 1)))
    fun notImplemented(index: Int = requests.lastIndex) = post(index, null)
    private fun post(index: Int, encoded: ByteBuffer?) {
        val readable = encoded?.apply { flip() }
        main.post { requests[index].reply?.reply(readable) }
    }
}
