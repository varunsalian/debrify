package com.debrify.app.tv

import android.content.Context
import android.view.View
import android.view.ViewGroup

/** Observe layout publication separately from mutating an already-shared LayoutParams object. */
internal class TvLayoutPublicationView(context: Context) : View(context) {
    var layoutWrites = 0
    override fun setLayoutParams(params: ViewGroup.LayoutParams?) {
        layoutWrites++
        super.setLayoutParams(params)
    }
}
