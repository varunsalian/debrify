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
import java.io.FilterOutputStream
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

	/** An open file on the share. Closing [output] logs off as well. */
	class Opened(
		val output: RecordingDestination.Output,
		val uri: Uri,
		val label: String,
		private val discard: () -> Unit,
	) {
		/** Removes the file again (a capture that saved nothing). */
		fun discard() = discard.invoke()
	}

	/**
	 * The share to record [ownerProfileId]'s capture to, or null when direct
	 * recording is off, unconfigured, another profile is active, or the saved
	 * password cannot be read (never log on with a wrong one: NAS lockouts).
	 */
	fun targetFor(context: Context, ownerProfileId: String): Target? {
		if (ProfilePreferenceProjection.activeJobContext(context).profileId != ownerProfileId) {
			return null
		}
		val raw = ProfilePreferenceProjection.getString(context, TARGET_KEY, null) ?: return null
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
		val sealed = ProfilePreferenceProjection.getString(context, PASSWORD_KEY, null)
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
				.withTimeout(20, TimeUnit.SECONDS)
				.withSoTimeout(60, TimeUnit.SECONDS)
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
			val stream = object : FilterOutputStream(file.outputStream) {
				override fun write(b: ByteArray, off: Int, len: Int) = out.write(b, off, len)

				override fun close() {
					// Each step separately: a dropped connection fails them all,
					// and none may keep the next from releasing its part.
					try { super.close() } catch (_: Exception) {}
					try { file.close() } catch (_: Exception) {}
					try { share.close() } catch (_: Exception) {}
					try { session.close() } catch (_: Exception) {}
					try { client.close() } catch (_: Exception) {}
				}
			}
			val uriPath = (listOf(target.share) + target.folder + name).joinToString("/")
			return Opened(
				output = RecordingDestination.Output(stream as OutputStream, null, null),
				uri = Uri.Builder().scheme("smb").authority(target.host).path("/$uriPath").build(),
				label = "${target.displayAddress}\\$name",
				discard = {
					// The server refuses to delete a file that is still open.
					try { file.close() } catch (_: Exception) {}
					try { share.rm(path) } catch (_: Exception) {}
				},
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
