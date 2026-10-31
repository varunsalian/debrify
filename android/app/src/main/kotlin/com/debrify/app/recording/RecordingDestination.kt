package com.debrify.app.recording

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.os.StatFs
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.io.FileDescriptor
import java.io.FileOutputStream
import java.io.OutputStream

/**
 * Where a background recording's bytes go. A folder the user picked with the
 * system folder picker (a SAF tree: a USB stick, or a network share exposed by
 * a documents-provider app) wins while its grant is still held and writable;
 * then a drive folder chosen in the app where there is no system picker (a
 * plain directory, see StorageVolumes); otherwise the default MediaStore
 * Download/Debrify/Recordings (API 29+) or the legacy public Downloads
 * folder. A chosen folder that went away never blocks a recording: it falls
 * back to the default.
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

	/**
	 * The chosen drive folder when it exists (or can be made), is writable and
	 * has room for a recording; a nearly full drive must not block one, so it
	 * falls back to the default folder. [path] defaults to the stored choice.
	 */
	fun usableDirectory(
		context: Context,
		path: String? = RecordingOutputPrefs.read(context).directoryPath,
	): File? {
		if (path == null) return null
		return try {
			val dir = File(path)
			val usable = dir.isAbsolute && (dir.isDirectory || dir.mkdirs()) && dir.canWrite()
			val room = runCatching { StatFs(dir.path).availableBytes }.getOrDefault(-1L)
			if (usable && room !in 0 until LiveRecordingService.MIN_FREE_BYTES) dir else null
		} catch (_: Exception) {
			null
		}
	}

	/** The chosen drive folder when it is there now, writable or not. */
	fun chosenDirectory(context: Context): File? =
		RecordingOutputPrefs.read(context).directoryPath?.let(::File)
			?.takeIf { it.isAbsolute && it.isDirectory }

	/**
	 * Recordings in [dir] the task store does not index ([covered] holds the
	 * paths it does), as unassigned library rows.
	 */
	fun unindexedFiles(dir: File, covered: Set<String>): List<Map<String, Any?>> {
		val files = runCatching { dir.listFiles() }.getOrNull() ?: return emptyList()
		return files.filter {
			it.isFile && it.absolutePath !in covered &&
				it.extension.lowercase() in setOf("ts", "mts", "m2ts", "mkv", "mp4")
		}.map { file ->
			mapOf(
				"taskId" to null,
				"uri" to Uri.fromFile(file).toString(),
				"name" to file.name,
				"channelName" to null,
				"bytes" to file.length(),
				"recordedAtMs" to file.lastModified(),
				"durationMs" to null,
				"ownerProfileId" to null,
				"ownershipState" to "unassigned",
			)
		}
	}

	/**
	 * Free bytes where the next recording will be written, or -1 when that is
	 * not knowable from here (a picked SAF folder: USB or network provider).
	 */
	fun freeBytes(context: Context): Long = try {
		when {
			usableTree(context) != null -> -1L
			else -> {
				@Suppress("DEPRECATION")
				val root = usableDirectory(context) ?: Environment.getExternalStorageDirectory()
				StatFs(root.path).availableBytes
			}
		}
	} catch (_: Exception) {
		-1L
	}

	/** Whether [uri] is a file outside the legacy Downloads folder: on a drive. */
	private fun onDrive(uri: Uri): Boolean {
		if (uri.scheme != "file") return false
		val parent = uri.path?.let { File(it).parentFile?.path } ?: return false
		return parent != LiveRecordingService.legacyRecordingsDir().path
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
		(if (allowTree) usableDirectory(context) else null)?.let { dir ->
			val created = createFileIn(dir, fileName)
			if (created is Created.Ok) return created
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
	private fun createLegacy(fileName: String): Created =
		createFileIn(LiveRecordingService.legacyRecordingsDir(), fileName)

	/** A fresh file name in [dir]; nothing is written until it is opened. */
	private fun createFileIn(dir: File, fileName: String): Created = try {
		if (!dir.exists() && !dir.mkdirs()) {
			Created.Failed("could not create recordings folder")
		} else {
			Created.Ok(Uri.fromFile(freeFile(dir, fileName)))
		}
	} catch (e: Exception) {
		Created.Failed(e.message ?: "could not create destination")
	}

	/** [fileName] in [dir], or "<name>_2.<ext>" and on when it is in use. */
	private fun freeFile(dir: File, fileName: String): File {
		var file = File(dir, fileName)
		val dot = fileName.lastIndexOf('.')
		val base = if (dot > 0) fileName.substring(0, dot) else fileName
		val ext = if (dot > 0) fileName.substring(dot) else ""
		var n = 2
		while (file.exists() && n < 100) {
			file = File(dir, "${base}_$n$ext")
			n++
		}
		return file
	}

	/**
	 * Moves a finished local [source] into the drive folder [path] (the
	 * caller's snapshot of the choice). Returns the new file's uri, or null
	 * (the source untouched) when the folder is gone, full or the copy fails.
	 */
	fun moveIntoDirectory(context: Context, source: File, fileName: String, path: String): Uri? {
		val dir = usableDirectory(context, path) ?: return null
		if (!source.isFile) return null
		val target = freeFile(dir, fileName)
		return try {
			source.inputStream().use { input ->
				FileOutputStream(target).use { output ->
					input.copyTo(output)
					output.fd.sync()
				}
			}
			runCatching { source.delete() }
			Uri.fromFile(target)
		} catch (_: Exception) {
			runCatching { target.delete() }
			null
		}
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
		if (onDrive(uri)) {
			// A drive that went read-only or away between create and open.
			runCatching { File(uri.path!!).takeIf { it.length() == 0L }?.delete() }
		} else if (isDocument(context, uri)) {
			try {
				DocumentsContract.deleteDocument(context.contentResolver, uri)
			} catch (_: Exception) {
			}
		} else {
			return null
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
		if (uri != null && SmbRecordingOutput.isShare(uri)) return SmbRecordingOutput.label(uri)
		if (uri != null && isDocument(context, uri)) {
			val tree = RecordingOutputPrefs.read(context).treeUri?.let(Uri::parse)
			val name = tree?.let {
				runCatching { DocumentFile.fromTreeUri(context, it)?.name }.getOrNull()
			}
			return name ?: "your chosen folder"
		}
		if (uri != null && onDrive(uri)) {
			// Named by the choice it was made under; a folder chosen since
			// then must not rename where this file actually is.
			val folder = File(uri.path!!).parentFile?.path
			val prefs = RecordingOutputPrefs.read(context)
			val chosen = prefs.directoryPath?.let { File(it).path }
			return (if (folder == chosen) prefs.folderLabel else null) ?: folder ?: "your chosen folder"
		}
		return "Downloads/Debrify/Recordings"
	}
}
