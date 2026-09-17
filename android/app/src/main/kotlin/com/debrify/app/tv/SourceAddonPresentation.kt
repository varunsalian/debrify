package com.debrify.app.tv

/** Mirrors Torrent.addonPresentation, preserving the addon's multiline text. */
internal fun sourceAddonPresentation(label: String?, originalTitle: String?, description: String?): Pair<String, String?>? {
    val name = label?.takeIf { it.isNotBlank() }
    val original = originalTitle?.takeIf { it.isNotBlank() }
    val detail = description?.takeIf { it.isNotBlank() }
    val heading = name ?: original ?: detail ?: return null
    return heading to (detail ?: original)?.takeIf { it != heading }
}
