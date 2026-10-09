package com.debrify.app.tv

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.nio.ByteBuffer
import java.util.concurrent.TimeUnit

/** Endpoint scripts preserve each caller's distinct null/send/reply-thread contract. */
internal class TvPhase14EndpointMessenger : BinaryMessenger {
    enum class Delivery { INLINE, QUEUED_MAIN, WORKER }
    data class Request(val channel: String, val call: MethodCall, val reply: BinaryMessenger.BinaryReply?)
    val requests = mutableListOf<Request>()
    val throwingEndpoints = mutableSetOf<String>()
    var onSend: ((Request) -> Unit)? = null
    private val main = Handler(Looper.getMainLooper())
    private val codec = StandardMethodCodec.INSTANCE
    @Volatile var replyThread: Thread? = null

    override fun send(channel: String, message: ByteBuffer?) = send(channel, message, null)
    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
        val call = codec.decodeMethodCall(message!!.duplicate().apply { flip() })
        if (call.method in throwingEndpoints) throw IllegalStateException("endpoint send failed: ${call.method}")
        val request = Request(channel, call, callback)
        requests.add(request)
        onSend?.invoke(request)
    }
    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit

    fun request(endpoint: String, occurrence: Int = -1): Request {
        val matches = requests.filter { it.call.method == endpoint }
        org.junit.Assert.assertTrue("Production sent $endpoint request $occurrence", matches.isNotEmpty() && (occurrence < 0 || occurrence < matches.size))
        return if (occurrence < 0) matches.last() else matches[occurrence]
    }
    fun success(endpoint: String, value: Any?, delivery: Delivery = Delivery.INLINE, occurrence: Int = -1) =
        answer(request(endpoint, occurrence), codec.encodeSuccessEnvelope(value), delivery)
    fun error(endpoint: String, message: String?, delivery: Delivery = Delivery.INLINE, occurrence: Int = -1) =
        answer(request(endpoint, occurrence), codec.encodeErrorEnvelope("server", message, null), delivery)
    fun unavailable(endpoint: String, delivery: Delivery = Delivery.INLINE, occurrence: Int = -1) =
        answer(request(endpoint, occurrence), null, delivery)
    fun answer(request: Request, encoded: ByteBuffer?, delivery: Delivery) {
        val readable = encoded?.apply { flip() }
        val reply = { replyThread = Thread.currentThread(); request.reply!!.reply(readable) }
        when (delivery) {
            Delivery.INLINE -> reply()
            Delivery.QUEUED_MAIN -> main.post { reply() }
            Delivery.WORKER -> {
                var failure: Throwable? = null
                val worker = Thread { try { reply() } catch (error: Throwable) { failure = error } }
                worker.start(); worker.join(TimeUnit.SECONDS.toMillis(5))
                check(!worker.isAlive) { "bounded worker reply did not return" }
                failure?.let { throw it }
            }
        }
    }
}
