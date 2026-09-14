package com.debrify.app.diagnostics

import java.io.File
import java.io.FileOutputStream

/** The caller serializes access. Leading newlines isolate a prior torn write;
 * replacement keeps an interrupted trim from erasing the original segment. */
internal object DiagnosticSegmentFile {
    fun append(file: File, record: String, sync: Boolean, maxBytes: Long) {
        FileOutputStream(file, true).use { output ->
            output.write(("\n" + record + "\n").toByteArray(Charsets.UTF_8))
            if (sync) output.fd.sync()
        }
        if (file.length() <= maxBytes) return
        val bytes = file.readBytes()
        var start = (bytes.size - (maxBytes / 2).toInt()).coerceAtLeast(0)
        while (start < bytes.size && bytes[start] != '\n'.code.toByte()) start++
        if (start < bytes.size) start++
        val replacement = File(file.parentFile, file.name + ".tmp")
        FileOutputStream(replacement).use { output ->
            output.write(bytes, start, bytes.size - start)
            output.fd.sync()
        }
        check(replacement.renameTo(file)) { "Diagnostic segment replacement failed" }
    }
}
