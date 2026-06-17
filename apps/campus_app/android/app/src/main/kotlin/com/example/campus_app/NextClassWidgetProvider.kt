package com.example.campus_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context

class NextClassWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        ScheduleWidgetManager.refreshAllWidgets(context)
    }

    override fun onEnabled(context: Context) {
        ScheduleWidgetManager.refreshAllWidgets(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        ScheduleWidgetManager.refreshAllWidgets(context)
    }
}
