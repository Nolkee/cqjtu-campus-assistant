package com.example.campus_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ClassReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        ClassReminderManager.handleReceiverIntent(context, intent)
    }
}
