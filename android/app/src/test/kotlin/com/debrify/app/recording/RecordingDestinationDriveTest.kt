package com.debrify.app.recording

import android.content.Context
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowStatFs
import java.io.File

/** A drive folder chosen without a system picker (Android TV boxes). */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [29])
class RecordingDestinationDriveTest {
	@get:Rule
	val temp = TemporaryFolder()

	private val context: Context = RuntimeEnvironment.getApplication()
	private lateinit var drive: File

	private fun store(json: String?) {
		context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().apply {
			clear()
			json?.let { putString("flutter.${RecordingOutputPrefs.KEY}", it) }
		}.commit()
	}

	/** 4 KiB blocks: plenty of room unless [freeBlocks] says otherwise. */
	private fun roomy(dir: File, freeBlocks: Int = 1_000_000) =
		ShadowStatFs.registerStats(dir, 2_000_000, freeBlocks, freeBlocks)

	@Before
	fun setUp() {
		drive = File(temp.root, "Recordings")
		roomy(drive)
		store("""{"directoryPath":"${drive.path}","treeDisplayName":"SanDisk USB"}""")
	}

	@Test
	fun aRecordingGoesIntoTheDriveFolderAndNamesIt() {
		val created = RecordingDestination.create(context, "news.ts", "video/mp2t")
		val uri = (created as RecordingDestination.Created.Ok).uri
		assertEquals("file", uri.scheme)
		assertEquals(File(drive, "news.ts").path, uri.path)
		// The folder is made on first use.
		assertTrue(drive.isDirectory)
		assertEquals("SanDisk USB", RecordingDestination.label(context, uri))
		// Free space is measured on the drive, not internal storage.
		roomy(drive, freeBlocks = 123_456)
		assertEquals(123_456L * 4096, RecordingDestination.freeBytes(context))
	}

	@Test
	fun aNameInUseStepsAside() {
		drive.mkdirs()
		File(drive, "news.ts").writeText("x")
		val uri = (RecordingDestination.create(context, "news.ts", "video/mp2t")
			as RecordingDestination.Created.Ok).uri
		assertEquals(File(drive, "news_2.ts").path, uri.path)
	}

	@Test
	@Config(sdk = [28])
	fun aDriveThatIsGoneFallsBackToTheDefaultFolder() {
		// A folder that can't be made: its "parent" is a plain file.
		val blocked = File(temp.newFile("not-a-folder"), "Recordings")
		store("""{"directoryPath":"${blocked.path}"}""")
		assertNull(RecordingDestination.usableDirectory(context))
		val uri = (RecordingDestination.create(context, "news.ts", "video/mp2t")
			as RecordingDestination.Created.Ok).uri
		assertEquals(LiveRecordingService.legacyRecordingsDir().path, File(uri.path!!).parent)
		assertEquals("Downloads/Debrify/Recordings", RecordingDestination.label(context, uri))
	}

	@Test
	@Config(sdk = [28])
	fun aNearlyFullDriveFallsBackRatherThanFailing() {
		drive.mkdirs()
		roomy(drive, freeBlocks = 10)
		assertNull(RecordingDestination.usableDirectory(context))
		val uri = (RecordingDestination.create(context, "news.ts", "video/mp2t")
			as RecordingDestination.Created.Ok).uri
		assertEquals(LiveRecordingService.legacyRecordingsDir().path, File(uri.path!!).parent)
	}

	@Test
	fun aFileFromAnEarlierChoiceKeepsItsOwnFolderName() {
		val old = File(temp.root, "OldDrive/Recordings/news.ts")
		assertEquals(old.parent, RecordingDestination.label(context, Uri.fromFile(old)))
	}

	@Test
	fun driveFilesNotInTheIndexAreListed() {
		drive.mkdirs()
		File(drive, "a.mkv").writeText("x")
		File(drive, "b.ts").writeText("x")
		File(drive, "notes.txt").writeText("x")
		val rows = RecordingDestination.unindexedFiles(drive, setOf(File(drive, "b.ts").absolutePath))
		assertEquals(listOf("a.mkv"), rows.map { it["name"] })
		assertEquals("unassigned", rows.single()["ownershipState"])
	}

	@Test
	fun aMissingFileOnAnUnmountedDriveIsUnknownNotGone() {
		// Not on any mounted volume: the drive is away, so the entry is kept.
		val away = Uri.fromFile(File("/storage/ABCD-1234/Android/data/x/files/Recordings/a.ts"))
		assertNull(RecordingTaskStore.destinationExists(context, away))
	}

	@Test
	fun aFinishedFileMovesOntoTheDrive() {
		val source = temp.newFile("capture.mkv").apply { writeText("video") }
		val moved = RecordingDestination.moveIntoDirectory(context, source, "capture.mkv", drive.path)
		assertNotNull(moved)
		assertEquals("video", File(moved!!.path!!).readText())
		assertFalse(source.exists())

		val kept = temp.newFile("other.mkv").apply { writeText("video") }
		val full = File(temp.root, "Full").apply { mkdirs() }
		roomy(full, freeBlocks = 1)
		assertNull(RecordingDestination.moveIntoDirectory(context, kept, "other.mkv", full.path))
		assertTrue(kept.exists())
	}
}
