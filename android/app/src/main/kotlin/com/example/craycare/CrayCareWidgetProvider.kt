package com.example.craycare

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.widget.RemoteViews

class CrayCareWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildViews(context))
        }
    }

    companion object {
        private const val PREFS_NAME = "craycare_live_widget"

        fun saveAndUpdate(context: Context, snapshot: Map<*, *>) {
            val editor = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            snapshot.forEach { (rawKey, value) ->
                val prefKey = rawKey as? String ?: return@forEach
                when (value) {
                    is Boolean -> editor.putBoolean(prefKey, value)
                    is String -> editor.putString(prefKey, value)
                    is Int -> editor.putInt(prefKey, value)
                    is Long -> editor.putLong(prefKey, value)
                    is Float -> editor.putFloat(prefKey, value)
                    is Double -> editor.putString(prefKey, value.toString())
                }
            }
            editor.apply()
            updateAllWidgets(context)
        }

        private fun updateAllWidgets(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, CrayCareWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { widgetId ->
                manager.updateAppWidget(widgetId, buildViews(context))
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.craycare_live_widget)
            val signedIn = prefs.getBoolean("widget_signed_in", false)
            val online = prefs.getBoolean("widget_online", false)

            setFlutterAsset(views, context, R.id.widget_logo, "assets/images/logo.png", 30)
            setFlutterAsset(views, context, R.id.widget_temp_icon, "assets/images/temperature.png", 22)
            setFlutterAsset(views, context, R.id.widget_ph_icon, "assets/images/pH.png", 22)
            setFlutterAsset(views, context, R.id.widget_do_icon, "assets/images/DO.png", 22)
            setFlutterAsset(views, context, R.id.widget_turb_icon, "assets/images/Turbidity.png", 22)
            setFlutterAsset(views, context, R.id.widget_water_icon, "assets/images/waterLevel.png", 22)
            setFlutterAsset(views, context, R.id.widget_feed_icon, "assets/images/FeedingImage.png", 18)

            views.setTextViewText(
                R.id.widget_online,
                if (online) "● ONLINE" else "● OFFLINE",
            )
            views.setTextColor(
                R.id.widget_online,
                if (online) Color.parseColor("#168B82") else Color.parseColor("#DC3545"),
            )

            val assessment = prefs.getString("widget_wqa", "WAITING") ?: "WAITING"
            views.setTextViewText(R.id.widget_assessment, assessment)
            views.setTextColor(R.id.widget_assessment, statusColor(assessment))
            views.setTextViewText(
                R.id.widget_concern,
                prefs.getString(
                    "widget_concern",
                    if (signedIn) "Collecting assessment history" else "Open CrayCare to sign in",
                ),
            )

            setSensor(views, prefs, "temperature", R.id.widget_temp_value, R.id.widget_temp_status)
            setSensor(views, prefs, "ph", R.id.widget_ph_value, R.id.widget_ph_status)
            setSensor(views, prefs, "dissolved_oxygen", R.id.widget_do_value, R.id.widget_do_status)
            setSensor(views, prefs, "turbidity", R.id.widget_turb_value, R.id.widget_turb_status)
            setSensor(views, prefs, "water_level", R.id.widget_water_value, R.id.widget_water_status)

            views.setTextViewText(
                R.id.widget_next_feed,
                prefs.getString("widget_next_feed", "No schedule"),
            )
            views.setTextViewText(
                R.id.widget_updated,
                prefs.getString("widget_updated", "--"),
            )

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openApp = PendingIntent.getActivity(
                context,
                4100,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openApp)
            return views
        }

        private fun setSensor(
            views: RemoteViews,
            prefs: android.content.SharedPreferences,
            sensor: String,
            valueView: Int,
            statusView: Int,
        ) {
            val value = prefs.getString("widget_${sensor}_value", "--") ?: "--"
            val status = prefs.getString("widget_${sensor}_status", "UNKNOWN") ?: "UNKNOWN"
            views.setTextViewText(valueView, value)
            views.setTextViewText(statusView, status)
            views.setTextColor(statusView, statusColor(status))
        }

        private fun statusColor(status: String): Int = when (status.uppercase()) {
            "NORMAL", "GOOD" -> Color.parseColor("#168B82")
            "WARNING", "MODERATE" -> Color.parseColor("#D48806")
            "CRITICAL", "POOR" -> Color.parseColor("#DC3545")
            else -> Color.parseColor("#7A8A94")
        }

        private fun setFlutterAsset(
            views: RemoteViews,
            context: Context,
            viewId: Int,
            assetPath: String,
            sizeDp: Int,
        ) {
            loadFlutterAsset(context, assetPath, sizeDp)?.let { bitmap ->
                views.setImageViewBitmap(viewId, bitmap)
            }
        }

        private fun loadFlutterAsset(
            context: Context,
            assetPath: String,
            sizeDp: Int,
        ): Bitmap? = try {
            val source = context.assets
                .open("flutter_assets/$assetPath")
                .use(BitmapFactory::decodeStream) ?: return null
            val sizePx = (sizeDp * context.resources.displayMetrics.density).toInt()
                .coerceAtLeast(1)
            val scaled = Bitmap.createScaledBitmap(source, sizePx, sizePx, true)
            if (scaled !== source) source.recycle()
            scaled
        } catch (_: Exception) {
            null
        }
    }
}
