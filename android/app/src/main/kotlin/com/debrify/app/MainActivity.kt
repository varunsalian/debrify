package com.debrify.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.app.UiModeManager
import android.content.res.Configuration
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayList
import org.json.JSONObject
import org.json.JSONArray

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Enable edge-to-edge display to properly handle system navigation bars
        WindowCompat.setDecorFitsSystemWindows(window, false)
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
            android.util.Log.d("DebrifyTV", "MainActivity: Method channel received: ${call.method}")
            when (call.method) {
                "launchTorboxPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchTorboxPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        android.util.Log.e("DebrifyTV", "MainActivity: Missing arguments")
                        result.error("bad_args", "Missing launch arguments", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTvPlayback(args, result, "torbox")
                }
                "launchRealDebridPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchRealDebridPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        android.util.Log.e("DebrifyTV", "MainActivity: Missing arguments")
                        result.error("bad_args", "Missing launch arguments", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTvPlayback(args, result, "real_debrid")
                }
                "launchTorrentPlayback" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling launchTorrentPlayback")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        result.error("bad_args", "Missing torrent payload", null)
                        return@setMethodCallHandler
                    }
                    handleLaunchTorrentPlayback(args, result)
                }
                "updateEpisodeMetadata" -> {
                    android.util.Log.d("DebrifyTV", "MainActivity: Handling updateEpisodeMetadata")
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments<Map<String, Any?>>()
                    if (args == null) {
                        result.error("bad_args", "Missing metadata updates", null)
                        return@setMethodCallHandler
                    }
                    handleUpdateEpisodeMetadata(args, result)
                }
                else -> {
                    android.util.Log.w("DebrifyTV", "MainActivity: Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        }
	}

    private fun handleLaunchTvPlayback(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
        provider: String
    ) {
        android.util.Log.d("DebrifyTV", "MainActivity: handleLaunchTvPlayback() called with provider=$provider")
        
        val initialUrl = (args["initialUrl"] as? String)?.trim()
        android.util.Log.d("DebrifyTV", "MainActivity: initialUrl=${initialUrl?.take(50)}...")
        
        if (initialUrl.isNullOrEmpty()) {
            android.util.Log.e("DebrifyTV", "MainActivity: initialUrl is null or empty")
            result.error("bad_args", "initialUrl is required", null)
            return
        }
        
        val initialTitleRaw = (args["initialTitle"] as? String)?.trim()
        val initialTitle = if (initialTitleRaw.isNullOrEmpty()) "Debrify TV" else initialTitleRaw
        android.util.Log.d("DebrifyTV", "MainActivity: title=$initialTitle")

        @Suppress("UNCHECKED_CAST")
        val config = args["config"] as? Map<String, Any?>
        android.util.Log.d("DebrifyTV", "MainActivity: config=$config")

        android.util.Log.d("DebrifyTV", "MainActivity: Creating intent for TorboxTvPlayerActivity")
        val intent = Intent().apply {
            setClassName(this@MainActivity, "com.debrify.app.tv.TorboxTvPlayerActivity")
            putExtra("initialUrl", initialUrl)
            putExtra("initialTitle", initialTitle)
            putExtra("provider", provider)
            putExtra("channelName", (args["channelName"] as? String)?.trim())
            putExtra("currentChannelId", (args["currentChannelId"] as? String)?.trim())
            (args["currentChannelNumber"] as? Number)?.toInt()?.let { number ->
                putExtra("currentChannelNumber", number)
            }

            @Suppress("UNCHECKED_CAST")
            val channelsRaw = args["channels"] as? List<Map<String, Any?>>
            if (!channelsRaw.isNullOrEmpty()) {
                android.util.Log.d(
                    "DebrifyTV",
                    "MainActivity: Preparing ${channelsRaw.size} channel directory entries",
                )
                val channelBundles = ArrayList<Bundle>(channelsRaw.size)
                channelsRaw.forEach { entry ->
                    val bundle = Bundle()
                    (entry["id"] as? String)?.trim()?.let { bundle.putString("id", it) }
                    (entry["name"] as? String)?.trim()?.let { bundle.putString("name", it) }
                    (entry["channelNumber"] as? Number)?.toInt()
                        ?.let { bundle.putInt("channelNumber", it) }
                    (entry["isCurrent"] as? Boolean)?.let { bundle.putBoolean("isCurrent", it) }
                    channelBundles.add(bundle)
                }
                if (channelBundles.isNotEmpty()) {
                    putParcelableArrayListExtra("channelDirectory", channelBundles)
                }
            }

            // For Torbox: magnets are required. For Real-Debrid: magnets are optional
            @Suppress("UNCHECKED_CAST")
            val magnetsRaw = args["magnets"] as? List<Map<String, Any?>>
            if (magnetsRaw != null && magnetsRaw.isNotEmpty()) {
                android.util.Log.d("DebrifyTV", "MainActivity: Processing ${magnetsRaw.size} magnets")
                val magnetBundles = ArrayList<Bundle>()
                magnetsRaw.forEach { entry ->
                    val magnet = (entry["magnet"] as? String)?.trim()
                    if (!magnet.isNullOrEmpty()) {
                        val bundle = Bundle()
                        bundle.putString("magnet", magnet)
                        bundle.putString("hash", (entry["hash"] as? String)?.trim() ?: "")
                        bundle.putString("name", (entry["name"] as? String)?.trim() ?: "")
                        (entry["sizeBytes"] as? Number)?.let { bundle.putLong("sizeBytes", it.toLong()) }
                        (entry["seeders"] as? Number)?.let { bundle.putInt("seeders", it.toInt()) }
                        magnetBundles.add(bundle)
                    }
                }
                if (magnetBundles.isNotEmpty()) {
                    android.util.Log.d("DebrifyTV", "MainActivity: Added ${magnetBundles.size} magnet bundles")
                    putParcelableArrayListExtra("magnetList", magnetBundles)
                }
            } else {
                android.util.Log.d("DebrifyTV", "MainActivity: No magnets provided (OK for Real-Debrid)")
            }
            
            putExtra("startFromRandom", config?.get("startFromRandom") as? Boolean ?: false)
            putExtra("randomStartMaxPercent", (config?.get("randomStartMaxPercent") as? Number)?.toInt() ?: 40)
            putExtra("hideSeekbar", config?.get("hideSeekbar") as? Boolean ?: false)
            putExtra("hideOptions", config?.get("hideOptions") as? Boolean ?: false)
            putExtra("showVideoTitle", config?.get("showVideoTitle") as? Boolean ?: true)
            putExtra("showChannelName", config?.get("showChannelName") as? Boolean ?: false)
        }

        try {
            android.util.Log.d("DebrifyTV", "MainActivity: Starting TorboxTvPlayerActivity")
            startActivity(intent)
            android.util.Log.d("DebrifyTV", "MainActivity: ✅ Activity started successfully")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("DebrifyTV", "MainActivity: ❌ Failed to start activity: ${e.message}")
            e.printStackTrace()
            result.error("launch_failed", e.message, null)
        }
    }

    private fun handleUpdateEpisodeMetadata(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        android.util.Log.d("TVMazeUpdate", "MainActivity: handleUpdateEpisodeMetadata CALLED")
        @Suppress("UNCHECKED_CAST")
        val updates = args["updates"] as? List<Map<String, Any?>>
        if (updates.isNullOrEmpty()) {
            android.util.Log.e("TVMazeUpdate", "MainActivity: updates is null or empty")
            result.error("bad_args", "updates is required", null)
            return
        }
        android.util.Log.d("TVMazeUpdate", "MainActivity: received ${updates.size} updates")

        try {
            // Broadcast intent to the active player activity
            val intent = Intent("com.debrify.app.tv.UPDATE_EPISODE_METADATA").apply {
                setPackage(packageName)
                val updatesJson = listToJson(updates).toString()
                android.util.Log.d("TVMazeUpdate", "MainActivity: updatesJson length=${updatesJson.length}")
                putExtra("metadataUpdates", updatesJson)
            }
            sendBroadcast(intent)
            android.util.Log.d("TVMazeUpdate", "MainActivity: Broadcast SENT with ${updates.size} updates")
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("TVMazeUpdate", "MainActivity: Failed to send metadata update: ${e.message}", e)
            result.error("update_failed", e.message, null)
        }
    }

    private fun handleLaunchTorrentPlayback(
        args: Map<String, Any?>,
        result: MethodChannel.Result,
    ) {
        val payload = args["payload"]
        if (payload !is Map<*, *>) {
            result.error("bad_args", "payload is required", null)
            return
        }

        try {
            val payloadJson = mapToJson(payload).toString()

            // Write payload to temp file to avoid Android's Intent size limit (~1MB)
            // This allows playlists with 500+ items without TransactionTooLargeException
            val tempFile = java.io.File(cacheDir, "torrent_payload_${System.currentTimeMillis()}.json")
            tempFile.writeText(payloadJson)
            android.util.Log.d("DebrifyTV", "MainActivity: Wrote payload to temp file: ${tempFile.absolutePath} (${payloadJson.length} bytes)")

            val intent = Intent().apply {
                setClassName(
                    this@MainActivity,
                    "com.debrify.app.tv.AndroidTvTorrentPlayerActivity",
                )
                putExtra("payloadPath", tempFile.absolutePath)
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            android.util.Log.e("DebrifyTV", "MainActivity: Failed to launch torrent playback", e)
            result.error("launch_failed", e.message, null)
        }
    }

    private fun mapToJson(map: Map<*, *>): org.json.JSONObject {
        val json = org.json.JSONObject()
        for ((key, value) in map) {
            if (key == null) continue
            json.put(key.toString(), valueToJson(value))
        }
        return json
    }

    private fun listToJson(list: List<*>): org.json.JSONArray {
        val array = org.json.JSONArray()
        for (value in list) {
            array.put(valueToJson(value))
        }
        return array
    }

    private fun valueToJson(value: Any?): Any? {
        return when (value) {
            null -> org.json.JSONObject.NULL
            is Map<*, *> -> mapToJson(value)
            is List<*> -> listToJson(value)
            is Number, is Boolean, is String -> value
            else -> value.toString()
        }
    }
}
