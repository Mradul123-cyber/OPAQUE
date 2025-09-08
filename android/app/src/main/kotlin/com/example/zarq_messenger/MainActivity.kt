package com.example.zarq_messenger  

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.zarq/signal"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ping" -> {
                        Log.d("MainActivity", "Ping received from Flutter")
                        result.success("pong")
                    }
                    else -> result.notImplemented()
                }
            }

        Log.d("MainActivity", "MethodChannel ready on $CHANNEL")
    }
}
