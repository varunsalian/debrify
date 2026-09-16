package com.debrify.app.storage

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.ArrayDeque
import java.util.concurrent.Executors

/** Persistent, read-only document access. Provider I/O never runs on the UI thread. */
class LocalSourceAccess(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "debrify/local_sources")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null
    private var disposed = false
    private val reader = LocalSourceDocumentReader(activity)
    private val operations = mutableMapOf<CancellationSignal, Runnable>()

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFile", "pickDirectory" -> {
                    if (pendingPick != null) {
                        result.error("busy", "A file picker is already open.", null)
                    } else {
                        val directory = call.method == "pickDirectory"
                        val intent = Intent(if (directory) Intent.ACTION_OPEN_DOCUMENT_TREE else Intent.ACTION_OPEN_DOCUMENT).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            if (!directory) {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                // Some providers label MKV/TS as application/octet-stream.
                                type = "*/*"
                            }
                        }
                        try {
                            pendingPick = result
                            activity.startActivityForResult(intent, REQUEST_PICK)
                        } catch (e: Exception) {
                            pendingPick = null
                            result.error("picker_unavailable", "No system file picker is available on this device.", null)
                        }
                    }
                }
                "stat", "listFiles" -> {
                    val raw = call.argument<String>("uri")
                    if (raw == null || Uri.parse(raw).scheme != "content") {
                        result.error("invalid_uri", "A document URI is required.", null)
                    } else {
                        run(result) { signal ->
                            val uri = Uri.parse(raw)
                            if (call.method == "stat") reader.stat(uri, signal) else reader.listFiles(uri, signal)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        run(result) { signal ->
            // A temporary grant is insufficient for a saved binding.
            activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            reader.stat(uri, signal)
        }
        return true
    }

    private fun run(result: MethodChannel.Result, operation: (CancellationSignal) -> Any?) {
        val signal = CancellationSignal()
        var completed = false // Accessed only on the main thread.
        val timeout = Runnable {
            if (!completed && !disposed) {
                completed = true
                operations.remove(signal)
                result.error("source_timeout", "Reading this source took too long. Try again or select a smaller folder.", null)
                signal.cancel()
            }
        }
        operations[signal] = timeout
        main.postDelayed(timeout, 30_000L)
        worker.execute {
            try {
                signal.throwIfCanceled()
                val value = operation(signal)
                main.post {
                    main.removeCallbacks(timeout)
                    operations.remove(signal)
                    if (!completed && !disposed) { completed = true; result.success(value) }
                }
            } catch (e: Exception) {
                val code = if (e is SecurityException) "permission_denied" else "source_unavailable"
                main.post {
                    main.removeCallbacks(timeout)
                    operations.remove(signal)
                    if (!completed && !disposed) {
                        completed = true
                        result.error(code, "Cannot read this local source. Reconnect the drive or select it again to grant access.", null)
                    }
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        operations.forEach { (signal, timeout) -> main.removeCallbacks(timeout); signal.cancel() }
        operations.clear()
        pendingPick?.error("activity_closed", "File picker was closed.", null)
        pendingPick = null
        channel.setMethodCallHandler(null)
        worker.shutdownNow()
    }

    companion object {
        private const val REQUEST_PICK = 51424
    }
}

internal class LocalSourceDocumentReader(private val context: android.content.Context) {
    private fun documentUri(uri: Uri): Uri =
        if (DocumentsContract.isTreeUri(uri) && "document" !in uri.pathSegments) {
            DocumentsContract.buildDocumentUriUsingTree(uri, DocumentsContract.getTreeDocumentId(uri))
        } else uri

    fun stat(uri: Uri, signal: CancellationSignal? = null): Map<String, Any> {
        val document = documentUri(uri)
        context.contentResolver.query(document, COLUMNS, null, null, null, signal)?.use { cursor ->
            if (!cursor.moveToFirst()) throw IOException("Document is unavailable")
            return row(cursor, uri.toString(), cursor.getString(1) ?: "Local source")
        }
        throw IOException("Document is unavailable")
    }

    private fun row(cursor: android.database.Cursor, uri: String, relative: String): Map<String, Any> = mapOf(
        "uri" to uri,
        "name" to (cursor.getString(1) ?: "Local source"),
        "relativePath" to relative,
        "isDirectory" to (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR),
        "sizeBytes" to (if (cursor.isNull(3)) 0L else cursor.getLong(3)),
        "modifiedAt" to (if (cursor.isNull(4)) 0L else cursor.getLong(4))
    )

    fun listFiles(tree: Uri, signal: CancellationSignal? = null): List<Map<String, Any>> {
        if (!DocumentsContract.isTreeUri(tree)) throw IOException("Select a folder")
        val root = stat(tree, signal)
        if (root["isDirectory"] != true) throw IOException("Not a folder")
        val pending = ArrayDeque<Triple<String, String, Int>>()
        pending.add(Triple(DocumentsContract.getDocumentId(documentUri(tree)), "", 0))
        val visited = mutableSetOf<String>()
        val files = mutableListOf<Map<String, Any>>()
        var entries = 0
        while (pending.isNotEmpty()) {
            signal?.throwIfCanceled()
            if (Thread.currentThread().isInterrupted) throw IOException("Cancelled")
            val (id, prefix, depth) = pending.removeFirst()
            if (!visited.add(id)) continue
            if (depth > 64) throw IOException("Folder nesting is too deep")
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, id)
            val cursor = context.contentResolver.query(children, COLUMNS, null, null, null, signal)
                ?: throw IOException("Folder is unavailable")
            cursor.use {
                if (it.extras.getBoolean(DocumentsContract.EXTRA_LOADING, false)) throw IOException("Folder is still loading")
                while (it.moveToNext()) {
                    if (++entries > 20000) throw IOException("Select a smaller folder")
                    val childId = it.getString(0) ?: throw IOException("Missing document identity")
                    val name = it.getString(1) ?: continue
                    val path = if (prefix.isEmpty()) name else "$prefix/$name"
                    if (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        pending.add(Triple(childId, path, depth + 1))
                    } else {
                        val childUri = DocumentsContract.buildDocumentUriUsingTree(tree, childId)
                        files.add(row(it, childUri.toString(), path))
                    }
                }
            }
        }
        return files
    }

    companion object {
        private val COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED
        )
    }
}
