package com.samionyx.ppg_recorder_app

import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Method channel `com.samionyx.ppg_recorder/native`:
 *  - `decodeVideoSignal {path, roiSize}` → per-frame ROI RGB means (runs on a
 *    background thread; progress is reported via `onDecodeProgress`).
 *  - `getFreeDiskSpace {path}` → available bytes on that volume.
 */
class PpgNativeChannel(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var disposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decodeVideoSignal" -> decodeVideoSignal(call, result)
            "getFreeDiskSpace" -> getFreeDiskSpace(call, result)
            else -> result.notImplemented()
        }
    }

    private fun decodeVideoSignal(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val roiSize = call.argument<Int>("roiSize") ?: DEFAULT_ROI
        if (path.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "A video path is required.", null)
            return
        }
        if (roiSize <= 0) {
            result.error("INVALID_ARGUMENT", "roiSize must be positive.", null)
            return
        }
        executor.execute {
            try {
                val decoded = VideoSignalDecoder(roiSize).decode(path) { progress ->
                    postToDart { channel.invokeMethod("onDecodeProgress", progress) }
                }
                postToDart { result.success(decoded.toMap()) }
            } catch (e: VideoDecodeException) {
                postToDart { result.error(e.code, e.message, null) }
            } catch (e: Throwable) {
                postToDart { result.error("DECODE_FAILED", e.message ?: e.toString(), null) }
            }
        }
    }

    private fun getFreeDiskSpace(call: MethodCall, result: MethodChannel.Result) {
        try {
            val path = call.argument<String>("path")
                ?: Environment.getDataDirectory().absolutePath
            result.success(StatFs(path).availableBytes)
        } catch (e: Exception) {
            result.error("STAT_FAILED", e.message ?: e.toString(), null)
        }
    }

    private fun postToDart(action: () -> Unit) {
        mainHandler.post {
            if (!disposed) action()
        }
    }

    /** Detaches from the engine and stops the worker thread. */
    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private companion object {
        const val CHANNEL_NAME = "com.samionyx.ppg_recorder/native"
        const val DEFAULT_ROI = 64
    }
}
