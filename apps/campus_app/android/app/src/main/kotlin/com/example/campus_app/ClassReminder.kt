package com.example.campus_app

import org.json.JSONObject

data class ClassReminder(
    val id: Int,
    val courseName: String,
    val classroom: String,
    val teacher: String,
    val timeText: String,
    val week: Int,
    val weekday: Int,
    val remindAtMillis: Long,
    val classStartAtMillis: Long,
    val isExam: Boolean = false,
    val seatNumber: String = "",
) {
    fun toJson(): JSONObject = JSONObject()
        .put("id", id)
        .put("courseName", courseName)
        .put("classroom", classroom)
        .put("teacher", teacher)
        .put("timeText", timeText)
        .put("week", week)
        .put("weekday", weekday)
        .put("remindAtMillis", remindAtMillis)
        .put("classStartAtMillis", classStartAtMillis)
        .put("isExam", isExam)
        .put("seatNumber", seatNumber)

    companion object {
        fun fromMap(map: Map<String, Any?>): ClassReminder = ClassReminder(
            id = intValue(map["id"]),
            courseName = stringValue(map["courseName"]),
            classroom = stringValue(map["classroom"]),
            teacher = stringValue(map["teacher"]),
            timeText = stringValue(map["timeText"]),
            week = intValue(map["week"]),
            weekday = intValue(map["weekday"]),
            remindAtMillis = longValue(map["remindAtMillis"]),
            classStartAtMillis = longValue(map["classStartAtMillis"]),
            isExam = boolValue(map["isExam"]),
            seatNumber = stringValue(map["seatNumber"]),
        )

        fun fromJson(json: JSONObject): ClassReminder = ClassReminder(
            id = json.optInt("id"),
            courseName = json.optString("courseName"),
            classroom = json.optString("classroom"),
            teacher = json.optString("teacher"),
            timeText = json.optString("timeText"),
            week = json.optInt("week"),
            weekday = json.optInt("weekday"),
            remindAtMillis = json.optLong("remindAtMillis"),
            classStartAtMillis = json.optLong("classStartAtMillis"),
            isExam = json.optBoolean("isExam", false),
            seatNumber = json.optString("seatNumber"),
        )

        private fun stringValue(value: Any?): String = value?.toString().orEmpty()

        private fun intValue(value: Any?): Int = when (value) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: 0
            else -> 0
        }

        private fun longValue(value: Any?): Long = when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull() ?: 0L
            else -> 0L
        }

        private fun boolValue(value: Any?): Boolean = when (value) {
            is Boolean -> value
            is Number -> value.toInt() != 0
            is String -> {
                val normalized = value.trim().lowercase()
                normalized == "true" || normalized == "1"
            }
            else -> false
        }
    }
}
