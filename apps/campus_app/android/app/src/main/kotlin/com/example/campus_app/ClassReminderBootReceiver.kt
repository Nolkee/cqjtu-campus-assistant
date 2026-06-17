package com.example.campus_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ClassReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        ClassReminderManager.restoreScheduledReminders(context)
    }
}
