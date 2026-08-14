package com.otorunners.ora.run

import android.util.Log

object RunDiagnostics {
    private const val LOG_TAG = "ORA_RUN"

    @Volatile
    private var enabled = false

    fun configure() {
        enabled = false
    }

    fun debug(message: () -> String) {
        if (enabled) Log.d(LOG_TAG, message())
    }
}
