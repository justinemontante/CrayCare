package com.example.craycare

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.craycare/app_settings",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openNotificationSettings") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    }
                } else {
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:$packageName"),
                    )
                }
                startActivity(intent)
                result.success(true)
            } catch (error: Exception) {
                result.error("OPEN_SETTINGS_FAILED", error.message, null)
            }
        }
    }
}
