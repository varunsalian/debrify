package com.debrify.app.storage

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.storage.StorageManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * The drives a folder can be chosen on where the device has no system folder
 * picker (many Android TV boxes ship without DocumentsUI's tree picker).
 * Lists this app's own folder on each removable volume: writable without any
 * permission, and removed by Android when the app is uninstalled.
 */
object StorageVolumes {
	const val CHANNEL = "debrify/storage_volumes"
	private val worker = Executors.newSingleThreadExecutor()
	private val main = Handler(Looper.getMainLooper())

	/** Binds the channel on [messenger]; a later engine simply binds again. */
	fun register(context: Context, messenger: BinaryMessenger) {
		val app = context.applicationContext
		MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
			when (call.method) {
				"canPickFolders" -> result.success(canPickFolders(app))
				"listVolumes" -> {
					val folder = call.argument<String>("folder") ?: "Recordings"
					// StatFs and volume lookups touch the disk: keep them off the UI thread.
					worker.execute {
						val volumes = try {
							listVolumes(app, folder)
						} catch (_: Exception) {
							emptyList()
						}
						main.post { result.success(volumes) }
					}
				}
				else -> result.notImplemented()
			}
		}
	}

	/** Whether a system folder picker (ACTION_OPEN_DOCUMENT_TREE) exists. */
	fun canPickFolders(context: Context): Boolean = try {
		Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).resolveActivity(context.packageManager) != null
	} catch (_: Exception) {
		false
	}

	/**
	 * One entry per mounted removable volume: [folder] inside this app's
	 * files directory there, its label, and free/total bytes. The primary
	 * volume is left out: its default Downloads folder outlives an
	 * uninstall, which this app-owned folder would not.
	 */
	fun listVolumes(context: Context, folder: String): List<Map<String, Any?>> {
		val manager = context.getSystemService(Context.STORAGE_SERVICE) as? StorageManager
		val out = ArrayList<Map<String, Any?>>()
		for (base in context.getExternalFilesDirs(null)) {
			// Null for a volume that is listed but not mounted right now.
			if (base == null) continue
			val removable = try {
				Environment.isExternalStorageRemovable(base)
			} catch (_: Exception) {
				false
			}
			if (!removable) continue
			val label = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
				runCatching { manager?.getStorageVolume(base)?.getDescription(context) }.getOrNull()
			} else {
				null
			}
			val stat = runCatching { StatFs(base.path) }.getOrNull()
			out.add(
				mapOf(
					"path" to File(base, folder).absolutePath,
					"label" to label?.takeIf { it.isNotBlank() },
					"freeBytes" to (stat?.availableBytes ?: -1L),
					"totalBytes" to (stat?.totalBytes ?: -1L),
				),
			)
		}
		return out
	}
}
