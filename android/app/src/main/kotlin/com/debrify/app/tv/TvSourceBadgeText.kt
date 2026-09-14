package com.debrify.app.tv

/** Keep the matcher input identical to Torrent.badgeDescription in Dart. */
internal fun sourceBadgeDescription(label: String?, description: String?): String? =
    listOfNotNull(label, description).filter { it.isNotEmpty() }
        .joinToString("\n").takeIf { it.isNotEmpty() }
