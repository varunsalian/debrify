package com.debrify.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.debrify.app/downloader"
	private val EVENTS = "com.debrify.app/downloader_events"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"startMediaStoreDownload" -> {
					val url = call.argument<String>("url")
					val fileName = call.argument<String>("fileName") ?: "download"
					val subDir = call.argument<String>("subDir") ?: "Debrify"
					val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
					@Suppress("UNCHECKED_CAST")
					val headers = call.argument<HashMap<String, String>>("headers") ?: hashMapOf()

					if (url.isNullOrEmpty()) {
						result.error("bad_args", "url is required", null)
						return@setMethodCallHandler
					}

					val taskId = System.currentTimeMillis().toString()
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_START
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_URL, url)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_FILE_NAME, fileName)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_RELATIVE_SUBDIR, subDir)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_MIME_TYPE, mimeType)
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_HEADERS, headers)
					}
					androidx.core.content.ContextCompat.startForegroundService(this, intent)
					result.success(taskId)
				}
				"pause" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_PAUSE
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					androidx.core.content.ContextCompat.startForegroundService(this, intent)
					result.success(true)
				}
				"resume" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_RESUME
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					androidx.core.content.ContextCompat.startForegroundService(this, intent)
					result.success(true)
				}
				"cancel" -> {
					val taskId = call.argument<String>("taskId")
					if (taskId.isNullOrEmpty()) { result.error("bad_args", "taskId required", null); return@setMethodCallHandler }
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_CANCEL
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					androidx.core.content.ContextCompat.startForegroundService(this, intent)
					result.success(true)
				}
				"openBatteryOptimizationSettings" -> {
					try {
						val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("open_failed", e.message, null)
					}
				}
				"requestIgnoreBatteryOptimizationForApp" -> {
					try {
						val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
							data = Uri.parse("package:" + packageName)
						}
						intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
						startActivity(intent)
						result.success(true)
					} catch (e: Exception) {
						result.error("request_failed", e.message, null)
					}
				}
				else -> result.notImplemented()
			}
		}

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(object: EventChannel.StreamHandler {
			override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
				com.debrify.app.download.ChannelBridge.setSink(events)
			}

			override fun onCancel(arguments: Any?) {
				com.debrify.app.download.ChannelBridge.setSink(null)
			}
		})
	}
} 