package com.example.craycare

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.craycare/home_widget",
        ).setMethodCallHandler { call, result ->
            if (call.method == "updateWidget") {
                val snapshot = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                CrayCareWidgetProvider.saveAndUpdate(this, snapshot)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }
}
