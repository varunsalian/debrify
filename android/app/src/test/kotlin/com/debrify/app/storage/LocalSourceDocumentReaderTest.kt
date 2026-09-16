package com.debrify.app.storage

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowContentResolver
import java.io.IOException

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class LocalSourceDocumentReaderTest {
    private lateinit var provider: TestProvider
    private lateinit var reader: LocalSourceDocumentReader
    private val tree = Uri.parse("content://local.test/tree/root%3Ashows")

    @Before fun setup() {
        provider = TestProvider()
        ShadowContentResolver.registerProviderInternal("local.test", provider)
        reader = LocalSourceDocumentReader(RuntimeEnvironment.getApplication())
        provider.documents["root:shows"] = doc("root:shows", "Show", true)
    }

    private fun doc(id: String, name: String, directory: Boolean = false): Array<Any> =
        arrayOf(id, name, if (directory) DocumentsContract.Document.MIME_TYPE_DIR else "video/x-matroska", 123L, 456L)

    @Test fun `nested files keep tree grant and relative display names`() {
        provider.children["root:shows"] = listOf(doc("opaque:season", "Season 2", true))
        provider.children["opaque:season"] = listOf(doc("opaque:file/one", "Show.S02E01.mkv"))
        val files = reader.listFiles(tree)
        assertEquals(1, files.size)
        assertEquals("Season 2/Show.S02E01.mkv", files.single()["relativePath"])
        assertEquals("content://local.test/tree/root%3Ashows/document/opaque%3Afile%2Fone", files.single()["uri"])
        assertEquals(123L, files.single()["sizeBytes"])
        assertEquals(tree.toString(), reader.stat(tree)["uri"])
    }

    @Test fun `stat of a child file does not stat the tree root`() {
        val uri = DocumentsContract.buildDocumentUriUsingTree(tree, "opaque:file")
        provider.documents["opaque:file"] = doc("opaque:file", "Movie.mkv")
        assertEquals("Movie.mkv", reader.stat(uri)["name"])
        assertEquals(false, reader.stat(uri)["isDirectory"])
    }

    @Test fun `permission loss is reported instead of an empty successful scan`() {
        provider.denied = true
        assertThrows(SecurityException::class.java) { reader.listFiles(tree) }
        provider.denied = false
        assertEquals(emptyList<Map<String, Any>>(), reader.listFiles(tree))
    }

    @Test fun `loading provider results are not mistaken for an empty folder`() {
        provider.loading = true
        assertThrows(IOException::class.java) { reader.listFiles(tree) }
    }

    @Test fun `missing root fails without silently returning an empty scan`() {
        provider.documents.clear()
        assertThrows(IOException::class.java) { reader.listFiles(tree) }
    }

    @Test fun `cyclic directory IDs do not cause an infinite scan`() {
        provider.children["root:shows"] = listOf(doc("root:shows", "loop", true), doc("file:one", "Show.S01E01.mkv"))
        assertEquals(1, reader.listFiles(tree).size)
    }

    class TestProvider : ContentProvider() {
        val documents = mutableMapOf<String, Array<Any>>()
        val children = mutableMapOf<String, List<Array<Any>>>()
        var denied = false
        var loading = false
        override fun onCreate() = true
        override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
            if (denied) throw SecurityException("Permission revoked")
            val cursor = MatrixCursor(projection!!)
            val id = DocumentsContract.getDocumentId(uri)
            if (uri.lastPathSegment == "children") {
                children[id].orEmpty().forEach { cursor.addRow(it) }
                if (loading) cursor.extras = Bundle().apply { putBoolean(DocumentsContract.EXTRA_LOADING, true) }
            } else documents[id]?.let { cursor.addRow(it) }
            return cursor
        }
        override fun getType(uri: Uri): String? = null
        override fun insert(uri: Uri, values: ContentValues?): Uri? = null
        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
        override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
    }
}
