package com.debrify.app.download

import android.content.ContentUris
import android.content.Context
import android.os.Build
import android.provider.MediaStore
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Only app-owned update artifacts predating a successful installation qualify. */
object UpdateApkCleanup {
    private val executor = Executors.newSingleThreadExecutor()
    private val running = AtomicBoolean(false)

    fun schedule(context: Context) {
        if (!running.compareAndSet(false, true)) return
        val app = context.applicationContext
        executor.execute {
            try { clean(app) } catch (_: Exception) {
                // Storage may be unavailable or ownership may have changed. Retry next launch.
            } finally { running.set(false) }
        }
    }

    internal fun eligible(
        packageName: String, installedPackage: String, version: Long,
        installedVersion: Long, modifiedSeconds: Long, installedAtMillis: Long,
    ): Boolean = packageName == installedPackage && version > 0 &&
        version <= installedVersion && modifiedSeconds > 0 &&
        // MediaStore timestamps have second precision; keep the boundary second.
        modifiedSeconds < installedAtMillis / 1000

    private fun clean(context: Context) {
        // The updater uses the MediaStore Downloads collection (Android 10+).
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val pm = context.packageManager
        val installed = pm.getPackageInfo(context.packageName, 0)
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val resolver = context.contentResolver
        val projection = arrayOf(MediaStore.Downloads._ID, MediaStore.Downloads.DATE_MODIFIED)
        val selection = "${MediaStore.Downloads.RELATIVE_PATH} = ? AND " +
            "${MediaStore.Downloads.OWNER_PACKAGE_NAME} = ? AND " +
            "${MediaStore.Downloads.IS_PENDING} = 0 AND " +
            "${MediaStore.Downloads.MIME_TYPE} = ? AND " +
            "${MediaStore.Downloads.DATE_MODIFIED} < ?"
        val args = arrayOf("Download/Debrify/Updates/", context.packageName,
            "application/vnd.android.package-archive", (installed.lastUpdateTime / 1000).toString())
        resolver.query(collection, projection, selection, args, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val uri = ContentUris.withAppendedId(collection, cursor.getLong(0))
                val modified = cursor.getLong(1)
                var scratch: File? = null
                try {
                    // PackageManager requires a filesystem path to inspect an APK.
                    val temp = File.createTempFile("update-inspection-", ".apk", context.cacheDir)
                    scratch = temp
                    resolver.openInputStream(uri)?.use { input ->
                        temp.outputStream().use { output ->
                            val buffer = ByteArray(64 * 1024)
                            var total = 0L
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                total += count
                                check(total <= 300L * 1024 * 1024)
                                output.write(buffer, 0, count)
                            }
                        }
                    } ?: continue
                    val archive = pm.getPackageArchiveInfo(temp.absolutePath, 0) ?: continue
                    if (eligible(archive.packageName, context.packageName, archive.longVersionCode,
                            installed.longVersionCode, modified, installed.lastUpdateTime)) {
                        resolver.delete(uri, null, null)
                    }
                } catch (_: Exception) {
                    // An unreadable or unrecognized file is retained.
                } finally { scratch?.delete() }
            }
        }
    }
}
