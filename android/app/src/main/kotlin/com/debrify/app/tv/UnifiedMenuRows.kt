package com.debrify.app.tv

internal fun mrow(
    title: String, value: String? = null, selected: Boolean = false, accent: Boolean = false,
    enabled: Boolean = true, swatch: Int? = null, adjustable: Boolean = false, tag: String? = null,
    onOk: (() -> Unit)? = null, onAdjust: ((Int) -> Unit)? = null
) = UnifiedMenuController.Row(title, value, selected, accent, enabled, swatch, adjustable, tag, onOk, onAdjust)
