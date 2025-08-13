package com.debrify.app.download

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object ChannelBridge {
	@Volatile
	private var eventSink: EventChannel.EventSink? = null
	private val mainHandler = Handler(Looper.getMainLooper())

	fun setSink(sink: EventChannel.EventSink?) {
		eventSink = sink
	}

	fun emit(event: Map<String, Any?>) {
		try {
			mainHandler.post {
				try {
					eventSink?.success(event)
				} catch (_: Exception) {}
			}
		} catch (_: Exception) {
			// ignore if no listeners
		}
	}
} 