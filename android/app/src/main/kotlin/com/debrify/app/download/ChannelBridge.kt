package com.debrify.app.download

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object ChannelBridge {
	@Volatile
	private var eventSink: EventChannel.EventSink? = null
	private val mainHandler = Handler(Looper.getMainLooper())

	// Terminal/transition events that arrive while the Flutter engine is
	// detached are buffered and replayed in order when a listener attaches, so
	// a download that completes in the background is not silently lost.
	// Progress events are NOT buffered — they are superseded by the next tick
	// and by the on-disk truth Dart reconciles against.
	private const val MAX_BUFFERED = 100
	private val buffer = ArrayDeque<Map<String, Any?>>()

	fun setSink(sink: EventChannel.EventSink?) {
		mainHandler.post {
			eventSink = sink
			if (sink != null) {
				val pending: List<Map<String, Any?>>
				synchronized(buffer) {
					pending = buffer.toList()
					buffer.clear()
				}
				pending.forEach { event ->
					try { sink.success(event) } catch (_: Exception) {}
				}
			}
		}
	}

	fun emit(event: Map<String, Any?>) {
		try {
			mainHandler.post {
				val sink = eventSink
				if (sink != null) {
					try { sink.success(event) } catch (_: Exception) {}
				} else if (event["type"] != "progress") {
					synchronized(buffer) {
						buffer.addLast(event)
						while (buffer.size > MAX_BUFFERED) buffer.removeFirst()
					}
				}
			}
		} catch (_: Exception) {
			// ignore if no listeners
		}
	}
}
