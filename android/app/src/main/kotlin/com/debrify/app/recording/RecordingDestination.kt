package com.debrify.app.recording

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import java.io.FileDescriptor
import java.io.FileOutputStream
import java.io.OutputStream

/**
 * Where a background recording's bytes go. A folder the user picked with the
 * system folder picker (a SAF tree: a USB stick, or a network share exposed by
 * a documents-provider app) wins while its grant is still held and writable;
 * otherwise the default MediaStore Download/Debrify/Recordings (API 29+) or
 * the legacy public Downloads folder. A picked folder that went away never
 * blocks a recording: it falls back to the default.
 */
object RecordingDestination {
	sealed class Created {
		data class Ok(val uri: Uri) : Created()
		data class Failed(val reason: String) : Created()
	}

	/** An open destination. [syncAndClose] makes the bytes durable first. */
	class Output(
		val stream: OutputStream,
		private val fd: FileDescriptor?,
		private val pfd: ParcelFileDescriptor?,
	) {
		fun syncAndClose() {
			try { stream.flush() } catch (_: Exception) {}
			try { fd?.sync() } catch (_: Exception) {}
			try { stream.close() } catch (_: Exception) {}
			try { pfd?.close() } catch (_: Exception) {}
		}
	}

	/** The picked folder when its grant is held and writable, else null. */
	fun usableTree(context: Context): Uri? {
		val raw = RecordingOutputPrefs.read(context).treeUri ?: return null
		return try {
			val tree = Uri.parse(raw)
			val granted = context.contentResolver.persistedUriPermissions.any {
				it.uri == tree && it.isWritePermission
			}
			val dir = if (granted) DocumentFile.fromTreeUri(context, tree) else null
			if (dir != null && dir.canWrite()) tree else null
		} catch (_: Exception) {
			null
		}
	}

	fun isDocument(context: Context, uri: Uri): Boolean =
		uri.scheme == "content" && DocumentsContract.isDocumentUri(context, uri)

	fun create(
		context: Context,
		fileName: String,
		mimeType: String,
		allowTree: Boolean = true,
	): Created {
		(if (allowTree) usableTree(context) else null)?.let { tree ->
			try {
				val parent = DocumentsContract.buildDocumentUriUsingTree(
					tree,
					DocumentsContract.getTreeDocumentId(tree),
				)
				// The provider de-duplicates the name itself ("x (1).ts").
				DocumentsContract.createDocument(
					context.contentResolver,
					parent,
					mimeType,
					fileName,
				)?.let { return Created.Ok(it) }
			} catch (_: Exception) {
				// Fall through to the default folder: a recording beats a choice.
			}
		}
		return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
			try {
				val values = ContentValues().apply {
					put(MediaStore.Downloads.DISPLAY_NAME, fileName)
					put(MediaStore.Downloads.MIME_TYPE, mimeType)
					put(MediaStore.Downloads.RELATIVE_PATH, LiveRecordingService.RELATIVE_PATH)
					put(MediaStore.Downloads.IS_PENDING, 1)
				}
				context.contentResolver
					.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
					?.let { Created.Ok(it) }
					?: Created.Failed("could not create destination")
			} catch (e: Exception) {
				Created.Failed(e.message ?: "could not create destination")
			}
		} else {
			createLegacy(fileName)
		}
	}

	// Legacy (API 21-28): a plain file in public Download/. No pending rows, no
	// publish step — a file that exists is already visible, which also
	// collapses the crash-reconcile story to a media scan.
	private fun createLegacy(fileName: String): Created = try {
		val dir = LiveRecordingService.legacyRecordingsDir()
		if (!dir.exists() && !dir.mkdirs()) {
			Created.Failed("could not create recordings folder")
		} else {
			var file = java.io.File(dir, fileName)
			// An existing file means "in use": step aside with a suffix.
			val base = fileName.removeSuffix(".ts")
			var n = 2
			while (file.exists() && n < 100) {
				file = java.io.File(dir, "${base}_$n.ts")
				n++
			}
			Created.Ok(Uri.fromFile(file))
		}
	} catch (e: Exception) {
		Created.Failed(e.message ?: "could not create destination")
	}

	/** Opens [uri] for writing, or null when the provider refuses. Never throws. */
	fun open(context: Context, uri: Uri): Output? = try {
		openOrThrow(context, uri)
	} catch (_: Exception) {
		null
	}

	/**
	 * Opens [uri]; when it is a picked-folder document the provider refuses
	 * (network/USB/read-only providers often accept createDocument but not
	 * writes), deletes that empty document and falls back to a fresh default
	 * destination. Returns the uri actually opened with its output, or null.
	 */
	fun openWithFallback(
		context: Context,
		uri: Uri,
		fileName: String,
		mimeType: String,
	): Pair<Uri, Output>? {
		open(context, uri)?.let { return uri to it }
		if (!isDocument(context, uri)) return null
		try {
			DocumentsContract.deleteDocument(context.contentResolver, uri)
		} catch (_: Exception) {
		}
		val fallback = create(context, fileName, mimeType, allowTree = false)
		if (fallback !is Created.Ok) return null
		return open(context, fallback.uri)?.let { fallback.uri to it }
	}

	private fun openOrThrow(context: Context, uri: Uri): Output? {
		if (uri.scheme == "file") {
			val fos = FileOutputStream(java.io.File(uri.path!!))
			return Output(fos, fos.fd, null)
		}
		if (isDocument(context, uri)) {
			// Network and removable providers often can't hand out a seekable
			// "rw" descriptor; a plain stream is all a capture needs.
			val stream = context.contentResolver.openOutputStream(uri, "w") ?: return null
			return Output(stream, null, null)
		}
		val pfd = context.contentResolver.openFileDescriptor(uri, "rw") ?: return null
		return Output(FileOutputStream(pfd.fileDescriptor), pfd.fileDescriptor, pfd)
	}

	/** Where a finished recording was saved, for the notification. */
	fun label(context: Context, uri: Uri?): String {
		if (uri != null && isDocument(context, uri)) {
			val tree = RecordingOutputPrefs.read(context).treeUri?.let(Uri::parse)
			val name = tree?.let {
				runCatching { DocumentFile.fromTreeUri(context, it)?.name }.getOrNull()
			}
			return name ?: "your chosen folder"
		}
		return "Downloads/Debrify/Recordings"
	}
}
