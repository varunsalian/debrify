package com.debrify.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.app.UiModeManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList
import com.debrify.app.tv.TorboxTvPlayerActivity

class MainActivity : FlutterActivity() {
	private val CHANNEL = "com.debrify.app/downloader"
	private val EVENTS = "com.debrify.app/downloader_events"
    private val ANDROID_TV_CHANNEL = "com.debrify.app/android_tv_player"

    companion object {
        @JvmStatic
        private var androidTvPlayerChannel: MethodChannel? = null

        @JvmStatic
        fun getAndroidTvPlayerChannel(): MethodChannel? = androidTvPlayerChannel

        @JvmStatic
        fun setAndroidTvPlayerChannel(channel: MethodChannel?) {
            androidTvPlayerChannel = channel
        }
    }

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

        val tvChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ANDROID_TV_CHANNEL
        )
        setAndroidTvPlayerChannel(tvChannel)
        tvChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "launchTorboxPlayback" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        result.error("bad_args", "Missing launch arguments", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTorboxPlayback(args, result)
                }
                else -> result.notImplemented()
            }
        }
	}

    private fun handleLaunchTorboxPlayback(
        args: Map<String, Any?>,
        result: MethodChannel.Result
    ) {
        val initialUrl = (args["initialUrl"] as? String)?.trim()
        if (initialUrl.isNullOrEmpty()) {
            result.error("bad_args", "initialUrl is required", null)
            return
        }
        val initialTitleRaw = (args["initialTitle"] as? String)?.trim()
        val initialTitle = if (initialTitleRaw.isNullOrEmpty()) "Debrify TV" else initialTitleRaw

        @Suppress("UNCHECKED_CAST")
        val magnetsRaw = args["magnets"] as? List<Map<String, Any?>>
        if (magnetsRaw == null || magnetsRaw.isEmpty()) {
            result.error("bad_args", "Magnets list is required", null)
            return
        }

        val magnetBundles = ArrayList<Bundle>()
        magnetsRaw.forEach { entry ->
            val magnet = (entry["magnet"] as? String)?.trim()
            if (magnet.isNullOrEmpty()) {
                return@forEach
            }
            val bundle = Bundle()
            bundle.putString("magnet", magnet)
            bundle.putString("hash", (entry["hash"] as? String)?.trim() ?: "")
            bundle.putString("name", (entry["name"] as? String)?.trim() ?: "")
            (entry["sizeBytes"] as? Number)?.let { bundle.putLong("sizeBytes", it.toLong()) }
            (entry["seeders"] as? Number)?.let { bundle.putInt("seeders", it.toInt()) }
            magnetBundles.add(bundle)
        }

        if (magnetBundles.isEmpty()) {
            result.error("bad_args", "No valid magnet entries", null)
            return
        }

        @Suppress("UNCHECKED_CAST")
        val config = args["config"] as? Map<String, Any?>
        val intent = Intent(this, TorboxTvPlayerActivity::class.java).apply {
            putExtra("initialUrl", initialUrl)
            putExtra("initialTitle", initialTitle)
            putParcelableArrayListExtra("magnetList", magnetBundles)
            putExtra(
                "startFromRandom",
                config?.get("startFromRandom") as? Boolean ?: false
            )
            putExtra(
                "randomStartMaxPercent",
                (config?.get("randomStartMaxPercent") as? Number)?.toInt() ?: 40
            )
            putExtra("hideSeekbar", config?.get("hideSeekbar") as? Boolean ?: false)
            putExtra("hideOptions", config?.get("hideOptions") as? Boolean ?: false)
            putExtra("showVideoTitle", config?.get("showVideoTitle") as? Boolean ?: true)
            putExtra("showWatermark", config?.get("showWatermark") as? Boolean ?: false)
            putExtra("hideBackButton", config?.get("hideBackButton") as? Boolean ?: false)
        }

        try {
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("launch_failed", e.message, null)
        }
    }
}
