package com.debrify.app.tv
import androidx.appcompat.app.AppCompatActivity
import android.widget.EditText
class Entry(var index: Int)
class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    fun receivers() {
        val entry = Entry(0)
        entry.apply { this.index = 7 }
        val item = Entry(0)
        item.apply { this.index = 9 }
        val input = EditText(this).apply {
            inputType = 2
        }
        check(entry.index == 7 && item.index == 9)
        check(input.inputType == 2)
    }
}
