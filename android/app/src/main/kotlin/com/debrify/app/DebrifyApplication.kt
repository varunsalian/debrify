package com.debrify.app

import android.app.Application
import android.content.Context
import android.system.Os
import android.util.Log

class DebrifyApplication : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        // SQLite's Unix defaults (/tmp, etc.) are not writable in Android's
        // app sandbox. Set its supported environment override before providers,
        // Flutter engines or database workers start. All isolates inherit it.
        // Use the cache root: cleanup jobs may remove temporary subdirectories.
        // Keep temp_store=FILE so large IPTV imports stay bounded in memory.
        Os.setenv("SQLITE_TMPDIR", cacheDir.absolutePath, true)
        Log.i("DebrifySQLite", "Temporary directory configured")
    }
}
