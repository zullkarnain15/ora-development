package com.otorunners.ora_flutter

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object TrackingEventBus {
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null

    fun attach(value: EventChannel.EventSink?) {
        sink = value
    }

    fun detach() {
        sink = null
    }

    fun emit(event: Map<String, Any?>) {
        mainHandler.post { sink?.success(event) }
    }
}
