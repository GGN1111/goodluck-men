package com.example.signalready_pocket

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signalready/model_asset")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractAsset" -> {
                        val asset = call.argument<String>("asset")
                        val dest = call.argument<String>("dest")
                        if (asset == null || dest == null) {
                            result.error("bad_args", "asset and dest are required", null)
                            return@setMethodCallHandler
                        }
                        Thread {
                            try {
                                val outFile = File(dest)
                                outFile.parentFile?.mkdirs()
                                var copied = 0L
                                assets.open(asset).use { input ->
                                    outFile.outputStream().use { output ->
                                        val buf = ByteArray(256 * 1024)
                                        while (true) {
                                            val n = input.read(buf)
                                            if (n < 0) break
                                            output.write(buf, 0, n)
                                            copied += n
                                        }
                                        output.fd.sync()
                                    }
                                }
                                Handler(Looper.getMainLooper()).post {
                                    result.success(copied)
                                }
                            } catch (t: Throwable) {
                                Handler(Looper.getMainLooper()).post {
                                    result.error("extract_failed", t.message, null)
                                }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
