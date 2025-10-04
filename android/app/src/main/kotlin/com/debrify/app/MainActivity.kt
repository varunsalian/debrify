package com.debrify.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.app.UiModeManager
import android.content.res.Configuration
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
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

					val taskId = UUID.randomUUID().toString()
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
					if (!hasPersistedDownload(taskId)) { result.success(false); return@setMethodCallHandler }
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
					if (!hasPersistedDownload(taskId)) { result.success(false); return@setMethodCallHandler }
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
					// Allow cancel even if state missing to ensure cleanup
					val intent = Intent(this, com.debrify.app.download.MediaStoreDownloadService::class.java).apply {
						action = com.debrify.app.download.MediaStoreDownloadService.ACTION_CANCEL
						putExtra(com.debrify.app.download.MediaStoreDownloadService.EXTRA_TASK_ID, taskId)
					}
					androidx.core.content.ContextCompat.startForegroundService(this, intent)
					result.success(true)
				}
				"drainNativeEvents" -> {
					result.success(drainPendingNativeEvents())
				}
				"openContentUri" -> {
					val uriStr = call.argument<String>("uri")
					val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
					if (uriStr.isNullOrEmpty()) {
						result.error("bad_args", "uri required", null)
						return@setMethodCallHandler
					}
					try {
						val u = Uri.parse(uriStr)
						val view = Intent(Intent.ACTION_VIEW).apply {
							setDataAndType(u, mime)
							addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
						}
						startActivity(view)
						result.success(true)
					} catch (e: ActivityNotFoundException) {
						try {
							val downloads = Intent("android.intent.action.VIEW_DOWNLOADS")
							downloads.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
							startActivity(downloads)
							result.success(false)
						} catch (e2: Exception) {
							result.error("open_failed", e2.message, null)
						}
					} catch (e: Exception) {
						result.error("open_failed", e.message, null)
					}
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
				"isTelevision" -> {
					try {
						val uiModeManager = getSystemService(UI_MODE_SERVICE) as UiModeManager
						val isTv = uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
						result.success(isTv)
					} catch (e: Exception) {
						result.success(false)
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

	private fun hasPersistedDownload(taskId: String): Boolean {
		val prefs = getSharedPreferences("med_store_dl_state", MODE_PRIVATE)
		return prefs.contains(taskId)
	}

	private fun drainPendingNativeEvents(): ArrayList<HashMap<String, Any?>> {
		val prefs = getSharedPreferences("med_store_dl_state", MODE_PRIVATE)
		val raw = prefs.getString("pending_events_queue", null)
		val result = arrayListOf<HashMap<String, Any?>>()
		if (!raw.isNullOrEmpty()) {
			try {
				val arr = JSONArray(raw)
				for (i in 0 until arr.length()) {
					val obj = arr.optJSONObject(i) ?: continue
					val map = HashMap<String, Any?>()
					val keys = obj.keys()
					while (keys.hasNext()) {
						val key = keys.next()
						map[key] = if (obj.isNull(key)) null else obj.get(key)
					}
					result.add(map)
				}
			} catch (_: Exception) {}
		}
		prefs.edit().remove("pending_events_queue").apply()
		return result
	}
}
