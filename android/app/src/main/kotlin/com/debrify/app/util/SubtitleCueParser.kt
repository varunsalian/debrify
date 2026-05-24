package com.debrify.app.util

data class SubtitleCue(
    val startMs: Long,
    val endMs: Long,
    val text: String
)

object SubtitleCueParser {

    fun parse(content: String, mimeType: String?): List<SubtitleCue> {
        val type = mimeType?.lowercase() ?: ""
        return when {
            type.contains("subrip") || type.contains("srt") -> parseSrt(content)
            type.contains("vtt") -> parseVtt(content)
            type.contains("ssa") || type.contains("ass") -> parseAss(content)
            else -> parseSrt(content)
        }
    }

    fun parseFromUrl(url: String): List<SubtitleCue> {
        val lower = url.lowercase()
        val content = try {
            java.net.URL(url).readText()
        } catch (e: Exception) {
            return emptyList()
        }
        return when {
            lower.contains(".srt") -> parseSrt(content)
            lower.contains(".vtt") -> parseVtt(content)
            lower.contains(".ass") || lower.contains(".ssa") -> parseAss(content)
            else -> parseSrt(content)
        }
    }

    private fun parseSrt(content: String): List<SubtitleCue> {
        val cues = mutableListOf<SubtitleCue>()
        val blocks = content.replace("\r\n", "\n").split(Regex("\\n\\s*\\n"))

        for (block in blocks) {
            val lines = block.trim().split("\n")
            if (lines.size < 2) continue

            var timingIdx = -1
            for (i in 0 until minOf(lines.size, 3)) {
                if (lines[i].contains("-->")) {
                    timingIdx = i
                    break
                }
            }
            if (timingIdx < 0) continue

            val parts = lines[timingIdx].split("-->")
            if (parts.size != 2) continue

            val startMs = parseTimestamp(parts[0].trim())
            val endMs = parseTimestamp(parts[1].trim())
            if (startMs < 0 || endMs < 0) continue

            val text = lines.subList(timingIdx + 1, lines.size)
                .joinToString("\n")
                .replace(Regex("<[^>]+>"), "")
                .replace(Regex("\\{[^}]+\\}"), "")
                .trim()
            if (text.isEmpty()) continue

            cues.add(SubtitleCue(startMs, endMs, text))
        }
        cues.sortBy { it.startMs }
        return cues
    }

    private fun parseVtt(content: String): List<SubtitleCue> {
        val cues = mutableListOf<SubtitleCue>()
        val normalized = content.replace("\r\n", "\n")
        val headerEnd = normalized.indexOf("\n\n")
        val body = if (headerEnd >= 0) normalized.substring(headerEnd + 2) else normalized
        val blocks = body.split(Regex("\\n\\s*\\n"))

        for (block in blocks) {
            val lines = block.trim().split("\n")
            if (lines.isEmpty()) continue

            var timingIdx = -1
            for (i in 0 until minOf(lines.size, 3)) {
                if (lines[i].contains("-->")) {
                    timingIdx = i
                    break
                }
            }
            if (timingIdx < 0) continue

            val parts = lines[timingIdx].split("-->")
            if (parts.size != 2) continue

            val startMs = parseTimestamp(parts[0].trim())
            val endMs = parseTimestamp(parts[1].trim())
            if (startMs < 0 || endMs < 0) continue

            val text = lines.subList(timingIdx + 1, lines.size)
                .joinToString("\n")
                .replace(Regex("<[^>]+>"), "")
                .trim()
            if (text.isEmpty()) continue

            cues.add(SubtitleCue(startMs, endMs, text))
        }
        cues.sortBy { it.startMs }
        return cues
    }

    private fun parseAss(content: String): List<SubtitleCue> {
        val cues = mutableListOf<SubtitleCue>()
        val lines = content.replace("\r\n", "\n").split("\n")

        var inEvents = false
        var textFieldIndex = -1
        var startFieldIndex = -1
        var endFieldIndex = -1

        for (line in lines) {
            val trimmed = line.trim()

            if (trimmed.lowercase() == "[events]") {
                inEvents = true
                continue
            }
            if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
                inEvents = false
                continue
            }
            if (!inEvents) continue

            if (trimmed.lowercase().startsWith("format:")) {
                val fields = trimmed.substring(7).split(",").map { it.trim().lowercase() }
                startFieldIndex = fields.indexOf("start")
                endFieldIndex = fields.indexOf("end")
                textFieldIndex = fields.indexOf("text")
                continue
            }

            if (!trimmed.lowercase().startsWith("dialogue:")) continue
            if (textFieldIndex < 0 || startFieldIndex < 0 || endFieldIndex < 0) continue

            val afterDialogue = trimmed.substring(trimmed.indexOf(':') + 1)
            val parts = mutableListOf<String>()
            var fieldStart = 0
            var commaCount = 0
            for (i in afterDialogue.indices) {
                if (afterDialogue[i] == ',' && commaCount < textFieldIndex) {
                    parts.add(afterDialogue.substring(fieldStart, i).trim())
                    fieldStart = i + 1
                    commaCount++
                }
            }
            parts.add(afterDialogue.substring(fieldStart).trim())

            if (parts.size <= textFieldIndex) continue

            val startMs = parseAssTimestamp(parts[startFieldIndex])
            val endMs = parseAssTimestamp(parts[endFieldIndex])
            if (startMs < 0 || endMs < 0) continue

            var text = parts[textFieldIndex]
            text = text.replace(Regex("\\{[^}]*\\}"), "")
            text = text.replace("\\N", "\n").replace("\\n", "\n")
            text = text.trim()
            if (text.isEmpty()) continue

            cues.add(SubtitleCue(startMs, endMs, text))
        }
        cues.sortBy { it.startMs }
        return cues
    }

    private fun parseTimestamp(ts: String): Long {
        val cleaned = ts.split(" ").first().replace(",", ".")
        val parts = cleaned.split(":")
        return try {
            when (parts.size) {
                3 -> {
                    val h = parts[0].toLong()
                    val m = parts[1].toLong()
                    val secParts = parts[2].split(".")
                    val s = secParts[0].toLong()
                    val ms = if (secParts.size > 1)
                        secParts[1].padEnd(3, '0').substring(0, 3).toLong()
                    else 0
                    h * 3600000 + m * 60000 + s * 1000 + ms
                }
                2 -> {
                    val m = parts[0].toLong()
                    val secParts = parts[1].split(".")
                    val s = secParts[0].toLong()
                    val ms = if (secParts.size > 1)
                        secParts[1].padEnd(3, '0').substring(0, 3).toLong()
                    else 0
                    m * 60000 + s * 1000 + ms
                }
                else -> -1
            }
        } catch (_: Exception) { -1 }
    }

    private fun parseAssTimestamp(ts: String): Long {
        val parts = ts.trim().split(":")
        if (parts.size != 3) return -1
        return try {
            val h = parts[0].toLong()
            val m = parts[1].toLong()
            val secParts = parts[2].split(".")
            val s = secParts[0].toLong()
            val cs = if (secParts.size > 1)
                secParts[1].padEnd(2, '0').substring(0, 2).toLong()
            else 0
            h * 3600000 + m * 60000 + s * 1000 + cs * 10
        } catch (_: Exception) { -1 }
    }
}
