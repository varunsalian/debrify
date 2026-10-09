package com.debrify.app.tv
import androidx.appcompat.app.AppCompatActivity
class AndroidTvTorrentPlayerActivity : AppCompatActivity() {
    var calls = 0
    override val layoutInflater: android.view.LayoutInflater
        get() { calls++; return super.layoutInflater }
    fun guideSkinBind(value: Int) { calls += value }
    fun exhaust() {
        layoutInflater.inflate()
        observer.addOnGlobalLayoutListener(object : android.view.ViewTreeObserver.OnGlobalLayoutListener {
            override fun onGlobalLayout() {
                observer.removeOnGlobalLayoutListener(this)
            }
        })
        val binder = ::guideSkinBind
        binder(7)
    }
}
