package com.samionyx.ppg_recorder_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var nativeChannel: PpgNativeChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        nativeChannel = PpgNativeChannel(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        nativeChannel?.dispose()
        nativeChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
