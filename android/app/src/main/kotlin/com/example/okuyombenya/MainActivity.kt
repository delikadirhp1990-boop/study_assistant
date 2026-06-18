package com.example.okuyombenya

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.okuyombenya/thumbnail"
    private val scope = CoroutineScope(Dispatchers.IO + Job())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "generateThumbnail" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null) {
                            result.error("INVALID_ARGUMENT", "filePath is null", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                val coverPath = ThumbnailGenerator.generateThumbnail(filePath)
                                withContext(Dispatchers.Main) {
                                    result.success(coverPath)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("GENERATION_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    "getFileInfo" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath == null) {
                            result.error("INVALID_ARGUMENT", "filePath is null", null)
                            return@setMethodCallHandler
                        }
                        scope.launch {
                            try {
                                val info = ThumbnailGenerator.getFileInfo(filePath)
                                withContext(Dispatchers.Main) {
                                    result.success(info)
                                }
                            } catch (e: Exception) {
                                withContext(Dispatchers.Main) {
                                    result.error("INFO_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }
}