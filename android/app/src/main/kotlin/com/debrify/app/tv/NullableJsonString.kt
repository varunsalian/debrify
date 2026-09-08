package com.debrify.app.tv

import org.json.JSONObject

/** Android optString coerces JSONObject.NULL to the nonempty string "null". */
internal fun JSONObject.nullableString(key: String): String? =
    if (isNull(key)) null else (opt(key) as? String)?.takeIf { it.isNotBlank() }
