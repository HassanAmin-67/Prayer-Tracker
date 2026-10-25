package com.example.prayer_tracker

import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class PrayerWidgetProvider : HomeWidgetProvider() {

    private val tapIds = intArrayOf(R.id.tap0, R.id.tap1, R.id.tap2, R.id.tap3, R.id.tap4)

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        // Wake the widget up at every prayer time so it redraws itself
        scheduleRefreshAlarms(context, widgetData.getString("refresh_times", "") ?: "")

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.prayer_widget).apply {
                // The day the widget is currently showing
                val day = widgetData.getString("widget_day", "") ?: ""

                // Tapping the label area opens the app on that day
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse("prayerwidget://open?d=$day")
                    )
                )

                // The picture Flutter drew
                val imagePath = widgetData.getString("prayer_widget_image", null)
                if (imagePath != null) {
                    val bitmap = BitmapFactory.decodeFile(imagePath)
                    if (bitmap != null) {
                        setImageViewBitmap(R.id.widget_image, bitmap)
                    }
                }

                // Each circle ticks that prayer for the day the picture shows
                for (i in 0..4) {
                    val uri = Uri.parse("prayerwidget://tick?d=$day&i=$i")
                    setOnClickPendingIntent(
                        tapIds[i],
                        HomeWidgetBackgroundIntent.getBroadcast(context, uri)
                    )
                }
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun scheduleRefreshAlarms(context: Context, csv: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        csv.split(",")
            .mapNotNull { it.trim().toLongOrNull() }
            .filter { it > now }
            .forEach { time ->
                val pending = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("prayerwidget://refresh?t=$time")
                )
                try {
                    alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, pending)
                } catch (e: SecurityException) {
                    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, time, pending)
                }
            }
    }
}