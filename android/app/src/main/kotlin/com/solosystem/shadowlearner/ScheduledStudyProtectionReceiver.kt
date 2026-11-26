package com.solosystem.shadowlearner

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Weekly Study Protection schedule boundaries. Runs independently of the Flutter
 * process; the AccessibilityService enforces the persisted scheduled-active flag.
 */
class ScheduledStudyProtectionReceiver : BroadcastReceiver() {
    companion object {
        const val PREFS = "solo_system_study_restriction"
        const val KEY_SCHEDULES = "study_protection_schedules"
        const val KEY_SCHEDULE_ACTIVE = "study_protection_schedule_active"
        private const val ACTION_BOUNDARY = "com.solosystem.shadowlearner.STUDY_BOUNDARY"
        private const val ACTION_BOOT = "android.intent.action.BOOT_COMPLETED"
        private const val ACTION_PACKAGE_REPLACED = "android.intent.action.MY_PACKAGE_REPLACED"
        private const val ACTION_TIME_CHANGED = "android.intent.action.TIME_SET"
        private const val ACTION_TIMEZONE_CHANGED = "android.intent.action.TIMEZONE_CHANGED"
        private const val TAG = "ShadowStudySchedule"

        fun sync(context: Context, schedules: List<Map<String, Any>>) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            // Cancel alarms belonging to the old list before replacing it, so
            // deleted or edited timetable entries cannot leave stale alarms.
            val previousSchedules = try {
                JSONArray(prefs.getString(KEY_SCHEDULES, "[]") ?: "[]")
            } catch (_: Exception) {
                JSONArray()
            }
            for (i in 0 until previousSchedules.length()) {
                val item = previousSchedules.optJSONObject(i) ?: continue
                val id = item.optString("id")
                cancelBoundary(context, alarm, requestCode(id, 0))
                cancelBoundary(context, alarm, requestCode(id, 1))
            }

            val array = JSONArray()
            schedules.forEach { item ->
                array.put(JSONObject().apply {
                    put("id", item["id"].toString())
                    put("dayOfWeek", (item["dayOfWeek"] as Number).toInt())
                    put("startTime", item["startTime"].toString())
                    put("durationMinutes", (item["durationMinutes"] as Number).toInt())
                    put("completedDate", item["completedDate"]?.toString() ?: "")
                })
            }
            prefs.edit().putString(KEY_SCHEDULES, array.toString()).apply()
            refresh(context)
        }

        private fun refresh(context: Context) {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val schedules = try {
                JSONArray(prefs.getString(KEY_SCHEDULES, "[]") ?: "[]")
            } catch (_: Exception) { JSONArray() }

            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            // Cancel all known start/end alarms before rebuilding the next boundary.
            for (i in 0 until schedules.length()) {
                val item = schedules.optJSONObject(i) ?: continue
                val id = item.optString("id")
                cancelBoundary(context, alarm, requestCode(id, 0))
                cancelBoundary(context, alarm, requestCode(id, 1))
            }

            val active = isWithinAnySchedule(schedules, Calendar.getInstance())
            prefs.edit().putBoolean(KEY_SCHEDULE_ACTIVE, active).apply()

            for (i in 0 until schedules.length()) {
                val item = schedules.optJSONObject(i) ?: continue
                val id = item.optString("id")
                val day = item.optInt("dayOfWeek")
                val parts = item.optString("startTime").split(":")
                if (parts.size != 2) continue
                val hour = parts[0].toIntOrNull() ?: continue
                val minute = parts[1].toIntOrNull() ?: continue
                val duration = item.optInt("durationMinutes")
                if (day !in 1..7 || duration <= 0) continue

                val now = Calendar.getInstance()
                val completedDate = item.optString("completedDate")
                if (completedDate == calendarDateKey(now)) {
                    // A quest completed early must not keep today's protection
                    // window active. Preserve only the next weekly occurrence.
                    val nextStart = nextOccurrence(day, hour, minute)
                    if (calendarDateKey(nextStart) == calendarDateKey(now)) {
                        nextStart.add(Calendar.DAY_OF_YEAR, 7)
                    }
                    val nextEnd = nextStart.clone() as Calendar
                    nextEnd.add(Calendar.MINUTE, duration)
                    setBoundary(context, alarm, requestCode(id, 0), nextStart.timeInMillis)
                    setBoundary(context, alarm, requestCode(id, 1), nextEnd.timeInMillis)
                    continue
                }

                val currentStart = occurrenceInCurrentWeek(day, hour, minute, now)
                val currentEnd = currentStart.clone() as Calendar
                currentEnd.add(Calendar.MINUTE, duration)
                if (currentEnd.after(now)) {
                    // If this schedule is already active, preserve today's end alarm.
                    // Otherwise schedule both upcoming boundaries.
                    if (currentStart.after(now)) {
                        setBoundary(context, alarm, requestCode(id, 0), currentStart.timeInMillis)
                    }
                    setBoundary(context, alarm, requestCode(id, 1), currentEnd.timeInMillis)
                } else {
                    val nextStart = nextOccurrence(day, hour, minute)
                    val nextEnd = nextStart.clone() as Calendar
                    nextEnd.add(Calendar.MINUTE, duration)
                    setBoundary(context, alarm, requestCode(id, 0), nextStart.timeInMillis)
                    setBoundary(context, alarm, requestCode(id, 1), nextEnd.timeInMillis)
                }
            }
            Log.i(TAG, "Study schedule refreshed; active=$active, count=${schedules.length()}")
        }

        private fun requestCode(id: String, edge: Int): Int =
            (id.hashCode() * 31 + edge) and 0x7fffffff

        private fun boundaryIntent(context: Context, requestCode: Int): PendingIntent {
            val intent = Intent(context, ScheduledStudyProtectionReceiver::class.java)
                .setAction(ACTION_BOUNDARY)
            return PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }

        private fun cancelBoundary(context: Context, alarm: AlarmManager, requestCode: Int) {
            val intent = Intent(context, ScheduledStudyProtectionReceiver::class.java)
                .setAction(ACTION_BOUNDARY)
            val pending = PendingIntent.getBroadcast(
                context, requestCode, intent,
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            )
            if (pending != null) {
                alarm.cancel(pending)
                pending.cancel()
            }
        }

        private fun setBoundary(
            context: Context, alarm: AlarmManager, requestCode: Int, atMillis: Long
        ) {
            val pending = boundaryIntent(context, requestCode)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !alarm.canScheduleExactAlarms()) {
                alarm.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            } else {
                alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)
            }
        }

        private fun occurrenceInCurrentWeek(
            dayOfWeek: Int, hour: Int, minute: Int, now: Calendar
        ): Calendar {
            val target = now.clone() as Calendar
            val androidDay = if (dayOfWeek == 7) Calendar.SUNDAY else dayOfWeek + 1
            val daysBack = (now.get(Calendar.DAY_OF_WEEK) - androidDay + 7) % 7
            target.add(Calendar.DAY_OF_YEAR, -daysBack)
            target.set(Calendar.HOUR_OF_DAY, hour)
            target.set(Calendar.MINUTE, minute)
            target.set(Calendar.SECOND, 0)
            target.set(Calendar.MILLISECOND, 0)
            if (target.after(now)) target.add(Calendar.DAY_OF_YEAR, -7)
            return target
        }

        private fun nextOccurrence(dayOfWeek: Int, hour: Int, minute: Int): Calendar {
            val now = Calendar.getInstance()
            val target = now.clone() as Calendar
            val androidDay = if (dayOfWeek == 7) Calendar.SUNDAY else dayOfWeek + 1
            var days = (androidDay - now.get(Calendar.DAY_OF_WEEK) + 7) % 7
            target.add(Calendar.DAY_OF_YEAR, days)
            target.set(Calendar.HOUR_OF_DAY, hour)
            target.set(Calendar.MINUTE, minute)
            target.set(Calendar.SECOND, 0)
            target.set(Calendar.MILLISECOND, 0)
            if (!target.after(now)) target.add(Calendar.DAY_OF_YEAR, 7)
            return target
        }

        private fun calendarDateKey(calendar: Calendar): String =
            String.format(
                java.util.Locale.US,
                "%04d-%02d-%02d",
                calendar.get(Calendar.YEAR),
                calendar.get(Calendar.MONTH) + 1,
                calendar.get(Calendar.DAY_OF_MONTH)
            )

        private fun isWithinAnySchedule(schedules: JSONArray, now: Calendar): Boolean {
            for (i in 0 until schedules.length()) {
                val item = schedules.optJSONObject(i) ?: continue
                val day = item.optInt("dayOfWeek")
                val parts = item.optString("startTime").split(":")
                if (day !in 1..7 || parts.size != 2) continue
                val hour = parts[0].toIntOrNull() ?: continue
                val minute = parts[1].toIntOrNull() ?: continue
                val duration = item.optInt("durationMinutes")
                val start = now.clone() as Calendar
                val todayFlutter = if (now.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY) 7
                    else now.get(Calendar.DAY_OF_WEEK) - 1
                val daysBack = (todayFlutter - day + 7) % 7
                // Also inspect yesterday's occurrence: a schedule may cross midnight.
                for (extraDay in 0..1) {
                    val occurrence = start.clone() as Calendar
                    occurrence.add(Calendar.DAY_OF_YEAR, -(daysBack + extraDay))
                    occurrence.set(Calendar.HOUR_OF_DAY, hour)
                    occurrence.set(Calendar.MINUTE, minute)
                    occurrence.set(Calendar.SECOND, 0)
                    occurrence.set(Calendar.MILLISECOND, 0)
                    // Completion suppresses only the occurrence on that date.
                    if (item.optString("completedDate") == calendarDateKey(occurrence)) {
                        continue
                    }
                    val end = occurrence.clone() as Calendar
                    end.add(Calendar.MINUTE, duration)
                    if (!now.before(occurrence) && now.before(end)) return true
                }
            }
            return false
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            ACTION_BOUNDARY,
            ACTION_BOOT,
            ACTION_PACKAGE_REPLACED,
            ACTION_TIME_CHANGED,
            ACTION_TIMEZONE_CHANGED -> refresh(context)
        }
    }
}
