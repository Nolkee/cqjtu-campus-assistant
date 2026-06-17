package com.example.campus_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ScheduleWidgetRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            ScheduleWidgetManager.ACTION_REFRESH,
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "MIUI.intent.action.QUICKBOOT_POWERON" -> {
                ScheduleWidgetManager.refreshAllWidgets(context)
            }
        }
    }
}
