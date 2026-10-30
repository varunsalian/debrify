package com.debrify.app.recording

import android.content.Context
import android.net.Uri
import com.debrify.app.profiles.ProfilePreferenceProjection
import com.debrify.app.security.SecretVaultReader
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.msfscc.FileAttributes
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2CreateOptions
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.security.bc.BCSecurityProvider
import com.hierynomus.smbj.share.DiskShare
import org.json.JSONObject
import java.io.IOException
import java.io.OutputStream
import java.util.concurrent.TimeUnit

/**
 * Writes a recording straight to the profile's SMB share (Settings ›
 * Recordings › Network share, "Record straight to the share"), so a capture
 * never has to fit on the device. The share and its login are profile-owned:
 * they are read from the active profile's native projection, and only for a
 * capture that profile owns. Anything unusable returns null and the capture
 * records locally, as before; the upload copies that file later.
 */
object SmbRecordingOutput {
	private const val TARGET_KEY = "recording_smb_target_v1"
	private const val PASSWORD_KEY = "recording_smb_password_v1"
	private const val MAX_NAME_SUFFIX = 99
	private const val LEGACY_OWNER = "legacy-admin-v1"

	/** Characters SMB forbids plus control characters (the Dart uploader's set). */
	private val ILLEGAL_NAME = Regex("[/\\\\:*?\"<>|\\x00-\\x1f]")

	/** The share, as Dart's SmbTarget stores it. */
	data class Target(
		val host: String,
		val share: String,
		val folder: List<String>,
		val user: String,
		val domain: String,
		val password: String?,
	) {
		/** `\\host\share\folder`. */
		val displayAddress: String
			get() = (listOf("\\\\$host", share) + folder).joinToString("\\")
	}

	/**
	 * The recording's file on the share. Bytes gather in memory and go out in
	 * [FLUSH_BYTES] writes at known offsets, so [confirmed] is exactly what
	 * the server acknowledged and a failed write can hand its bytes back
	 * ([takeUnsent]) to a local file. [close] logs off; [abort] drops the
	 * connection without waiting on a server that stopped answering.
	 */
	class ShareStream internal constructor(
		private val file: com.hierynomus.smbj.share.File,
		private val path: String,
		private val share: DiskShare,
		private val connection: com.hierynomus.smbj.connection.Connection,
		private val client: SMBClient,
	) : OutputStream() {
		private val pending = java.io.ByteArrayOutputStream()

		@Volatile var confirmed = 0L
			private set

		override fun write(b: Int) = write(byteArrayOf(b.toByte()), 0, 1)

		override fun write(b: ByteArray, off: Int, len: Int) {
			pending.write(b, off, len)
			if (pending.size() >= FLUSH_BYTES) flush()
		}

		/** Sends what is gathered; on failure it stays for [takeUnsent]. */
		override fun flush() {
			if (pending.size() == 0) return
			val data = pending.toByteArray()
			file.write(data, confirmed)
			confirmed += data.size
			pending.reset()
		}

		fun takeUnsent(): ByteArray = pending.toByteArray().also { pending.reset() }

		/** Flushes, removes the file if nothing reached it, and logs off. */
		override fun close() {
			try { flush() } finally {
				try { file.close() } catch (_: Exception) {}
				if (confirmed == 0L) try { share.rm(path) } catch (_: Exception) {}
				try { client.close() } catch (_: Exception) {}
			}
		}

		fun abort() {
			try { connection.close(true) } catch (_: Exception) {}
			try { client.close() } catch (_: Exception) {}
		}
	}

	/** An open file on the share; [stream] is also what [output] writes to. */
	class Opened(val stream: ShareStream, val uri: Uri, val label: String) {
		val output = RecordingDestination.Output(stream, null, null)
	}

	/** Bytes gathered per write: one round trip per network read would cap throughput. */
	private const val FLUSH_BYTES = 1024 * 1024

	/**
	 * The share to record [ownerProfileId]'s capture to, or null when direct
	 * recording is off, unconfigured, another profile is active, or the saved
	 * password cannot be read (never log on with a wrong one: NAS lockouts).
	 */
	fun targetFor(context: Context, ownerProfileId: String): Target? {
		// One snapshot for the owner check and both values: separate reads could
		// pair this capture with a profile that took over in between.
		val snapshot = ProfilePreferenceProjection.activeSnapshot(context)
		val values: (String) -> String? = if (snapshot != null) {
			if (snapshot.optString("profileId") != ownerProfileId) return null
			val projected = snapshot.optJSONObject("values")
			({ key -> projected?.opt(key) as? String })
		} else {
			// Single-profile (legacy) installs keep plain Flutter preferences.
			if (ProfilePreferenceProjection.isCommitted(context) || ownerProfileId != LEGACY_OWNER) return null
			({ key -> ProfilePreferenceProjection.getString(context, key, null) })
		}
		val raw = values(TARGET_KEY) ?: return null
		val json = try { JSONObject(raw) } catch (_: Exception) { return null }
		if (!json.optBoolean("enabled", false) || !json.optBoolean("recordDirect", true)) {
			return null
		}
		val host = json.optString("host").trim()
		val share = json.optString("share").trim()
		if (host.isEmpty() || share.isEmpty() || share.contains('/') || share.contains('\\')) {
			return null
		}
		val folder = json.optString("folder").replace('\\', '/').split('/')
			.map { it.trim() }
			.filter { it.isNotEmpty() && it != "." && it != ".." }
		val sealed = values(PASSWORD_KEY)
		val password = if (sealed == null) null else {
			SecretVaultReader.open(context, sealed) ?: return null
		}
		return Target(
			host = host,
			share = share,
			folder = folder,
			user = json.optString("user").trim(),
			domain = json.optString("domain").trim(),
			password = password,
		)
	}

	/**
	 * Connects, creates the folder and a new file named after [fileName]
	 * (`x (2).ts` when taken). Null when the share cannot be used. Blocking:
	 * call from the capture thread.
	 */
	fun open(target: Target, fileName: String): Opened? {
		val client = SMBClient(
			SmbConfig.builder()
				// A stalled server fails a write after this; the capture then
				// continues locally. No socket timeout: a silent channel must not
				// end an idle session mid-recording.
				.withTimeout(20, TimeUnit.SECONDS)
				// Android's JCE has no MD4, which NTLM needs.
				.withSecurityProvider(BCSecurityProvider())
				.build(),
		)
		try {
			val connection = client.connect(target.host)
			val auth = if (target.user.isEmpty()) {
				AuthenticationContext.anonymous()
			} else {
				AuthenticationContext(
					target.user,
					(target.password ?: "").toCharArray(),
					target.domain.ifEmpty { null },
				)
			}
			val session = connection.authenticate(auth)
			val share = session.connectShare(target.share) as? DiskShare
				?: throw IOException("${target.share} is not a folder share")
			var folderPath = ""
			for (segment in target.folder) {
				folderPath = if (folderPath.isEmpty()) segment else "$folderPath\\$segment"
				if (!share.folderExists(folderPath)) {
					try {
						share.mkdir(folderPath)
					} catch (e: Exception) {
						// Another client may have made it in between.
						if (!share.folderExists(folderPath)) throw e
					}
				}
			}
			val name = freeName(share, folderPath, fileName)
				?: throw IOException("no free file name")
			val path = if (folderPath.isEmpty()) name else "$folderPath\\$name"
			val file = share.openFile(
				path,
				setOf(AccessMask.GENERIC_WRITE),
				setOf(FileAttributes.FILE_ATTRIBUTE_NORMAL),
				// Others may read (play) it while it is being written.
				setOf(SMB2ShareAccess.FILE_SHARE_READ),
				SMB2CreateDisposition.FILE_CREATE,
				setOf(SMB2CreateOptions.FILE_NON_DIRECTORY_FILE),
			)
			val uriPath = (listOf(target.share) + target.folder + name).joinToString("/")
			return Opened(
				stream = ShareStream(file, path, share, connection, client),
				uri = Uri.Builder().scheme("smb").authority(target.host).path("/$uriPath").build(),
				label = "${target.displayAddress}\\$name",
			)
		} catch (e: Exception) {
			android.util.Log.w("Recording", "share unavailable, recording locally: ${e.message}")
			try { client.close() } catch (_: Exception) {}
			return null
		}
	}

	/** `\\host\share\path` for an `smb://host/share/path` uri. */
	fun label(uri: Uri): String =
		"\\\\${uri.host}" + (uri.path ?: "").replace('/', '\\')

	fun isShare(uri: Uri?): Boolean = uri?.scheme == "smb"

	private fun freeName(share: DiskShare, folderPath: String, fileName: String): String? {
		var name = fileName.replace(ILLEGAL_NAME, "_")
		if (name.isEmpty()) name = "recording.ts"
		fun taken(candidate: String) =
			share.fileExists(if (folderPath.isEmpty()) candidate else "$folderPath\\$candidate")
		if (!taken(name)) return name
		val dot = name.lastIndexOf('.')
		val stem = if (dot > 0) name.substring(0, dot) else name
		val ext = if (dot > 0) name.substring(dot) else ""
		for (i in 2..MAX_NAME_SUFFIX) {
			val candidate = "$stem ($i)$ext"
			if (!taken(candidate)) return candidate
		}
		return null
	}
}
