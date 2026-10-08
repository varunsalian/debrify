package com.debrify.app.tv

import androidx.appcompat.app.AppCompatActivity
import android.widget.EditText
import androidx.core.widget.TextViewCompat

class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    var resourceReads = 0
    var focusReads = 0
    override val resources: android.content.res.Resources
        get() { resourceReads++; return super.resources }
    override val currentFocus: android.view.View?
        get() { focusReads++; return super.currentFocus }

    fun exhaust() {
        val input = EditText(this).apply {
            TextViewCompat.setCompoundDrawableTintList(this, 1)
        }
        val height = resources.heightPixels
        val focused = currentFocus
        check(height == 42 && focused != null && TextViewCompat.last === input)
    }
}
