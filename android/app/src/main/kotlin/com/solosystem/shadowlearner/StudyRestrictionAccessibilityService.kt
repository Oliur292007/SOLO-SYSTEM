package com.solosystem.shadowlearner

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

/**
 * Shared foreground guard for daily Screen Time limits and active study sessions.
 * Screen Time limits apply all day; Study Protection applies only while a quest
 * focus session is active. YouTube and approved education apps are study-safe.
 */
class StudyRestrictionAccessibilityService : AccessibilityService() {
    companion object {
        const val PREFS = "solo_system_study_restriction"
        const val KEY_ACTIVE = "study_restriction_active"
        private const val WARNING_CHANNEL_ID = "solo_youtube_study_warnings"
        private const val WARNING_NOTIFICATION_ID = 54001
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastRedirectAt = 0L
    private var lastBlockedPackage: String? = null
    private var currentForegroundPackage: String? = null
    private var currentSessionUsageMs = 0L
    private var lastUsageTickElapsed = 0L
    private var currentUsageDay = usageDayKey()
    private var youtubeWarningRunnable: Runnable? = null

    private val screenTimeCheck = object : Runnable {
        override fun run() {
            val packageName = currentForegroundPackage
            val nowElapsed = SystemClock.elapsedRealtime()
            val today = usageDayKey()
            if (today != currentUsageDay) {
                currentUsageDay = today
                currentSessionUsageMs = if (packageName == null) 0L else
                    ScreenTimePolicy.usageByPackage(this@StudyRestrictionAccessibilityService)[packageName] ?: 0L
                lastUsageTickElapsed = nowElapsed
            }
            if (lastUsageTickElapsed > 0L && isScreenInteractive()) {
                currentSessionUsageMs += (nowElapsed - lastUsageTickElapsed).coerceAtLeast(0L)
            }
            lastUsageTickElapsed = nowElapsed

            val studyActive = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getBoolean(KEY_ACTIVE, false)
            if (packageName == "com.google.android.youtube" && studyActive) {
                startYouTubeWarnings()
            } else {
                stopYouTubeWarnings()
            }

            if (packageName != null && !isSystemAllowedPackage(packageName)) {
                val reportedUsage = ScreenTimePolicy.usageByPackage(
                    this@StudyRestrictionAccessibilityService
                )[packageName] ?: 0L
                val usedMs = maxOf(reportedUsage, currentSessionUsageMs)
                if (ScreenTimePolicy.limitReachedForUsage(
                        this@StudyRestrictionAccessibilityService,
                        packageName,
                        usedMs
                    )
                ) {
                    redirectHome(packageName)
                }
            }
            handler.postDelayed(this, 10_000L)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo.apply {
            eventTypes =
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOWS_CHANGED
            notificationTimeout = 80L
        }
        lastRedirectAt = 0L
        lastBlockedPackage = null
        handler.removeCallbacks(screenTimeCheck)
        handler.postDelayed(screenTimeCheck, 10_000L)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
        ) return

        val foregroundPackage = rootInActiveWindow?.packageName?.toString()
            ?.takeIf { it.isNotBlank() }
        val openedPackage = foregroundPackage
            ?: event.packageName?.toString()?.takeIf { it.isNotBlank() }
            ?: return

        if (currentForegroundPackage != openedPackage) {
            currentForegroundPackage = openedPackage
            currentSessionUsageMs =
                ScreenTimePolicy.usageByPackage(this)[openedPackage] ?: 0L
            lastUsageTickElapsed = SystemClock.elapsedRealtime()
        }
        val studyProtectionActive = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getBoolean(KEY_ACTIVE, false)

        if (openedPackage == "com.google.android.youtube" && studyProtectionActive) {
            startYouTubeWarnings()
        } else {
            stopYouTubeWarnings()
        }

        if (isSystemAllowedPackage(openedPackage)) return

        // Daily category limits apply even when Study Protection is inactive.
        if (ScreenTimePolicy.isLimitReached(this, openedPackage)) {
            redirectHome(openedPackage)
            return
        }

        // During focus sessions, only the app's approved whitelist is accessible.
        if (studyProtectionActive &&
            !ScreenTimePolicy.isStudyAllowed(this, openedPackage)
        ) {
            redirectHome(openedPackage)
        }
    }

    private fun redirectHome(packageName: String) {
        val now = System.currentTimeMillis()
        if (packageName == lastBlockedPackage && now - lastRedirectAt < 900L) return
        if (now - lastRedirectAt < 450L) return

        lastBlockedPackage = packageName
        lastRedirectAt = now

        val movedHome = performGlobalAction(GLOBAL_ACTION_HOME)
        if (!movedHome) {
            runCatching {
                startActivity(
                    Intent(Intent.ACTION_MAIN).apply {
                        addCategory(Intent.CATEGORY_HOME)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
            }
        }
    }

    private fun startYouTubeWarnings() {
        if (youtubeWarningRunnable != null) return
        val intervalMs = ScreenTimePolicy.youtubeWarningMinutes(this) * 60_000L
        val runnable = object : Runnable {
            override fun run() {
                val active = getSharedPreferences(PREFS, MODE_PRIVATE)
                    .getBoolean(KEY_ACTIVE, false)
                if (!active || currentForegroundPackage != "com.google.android.youtube") {
                    stopYouTubeWarnings()
                    return
                }
                showYouTubeWarning()
                handler.postDelayed(this, intervalMs)
            }
        }
        youtubeWarningRunnable = runnable
        handler.postDelayed(runnable, intervalMs)
    }

    private fun stopYouTubeWarnings() {
        youtubeWarningRunnable?.let(handler::removeCallbacks)
        youtubeWarningRunnable = null
    }

    private fun showYouTubeWarning() {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                WARNING_CHANNEL_ID,
                "YouTube Study Warnings",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Periodic reminders while YouTube is open during Study Protection."
            }
            manager.createNotificationChannel(channel)
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                WARNING_NOTIFICATION_ID,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, WARNING_CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        val notification = builder.setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("STUDY PROTECTION REMINDER")
            .setContentText("YouTube is unlocked, but your study session is still active. Return to your mission.")
            .setStyle(
                Notification.BigTextStyle().bigText(
                    "YouTube remains accessible as requested. This is your periodic 5-minute reminder to return to your study mission."
                )
            )
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        runCatching { manager.notify(WARNING_NOTIFICATION_ID, notification) }
    }

    private fun usageDayKey(): String =
        java.text.SimpleDateFormat("yyyyMMdd", java.util.Locale.getDefault())
            .format(java.util.Date())

    private fun isScreenInteractive(): Boolean {
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        return power.isInteractive
    }

    private fun isSystemAllowedPackage(packageName: String): Boolean {
        if (packageName == this.packageName) return true
        val p = packageName.lowercase()
        return p.contains("launcher") ||
            p.contains("systemui") ||
            p.contains("permissioncontroller") ||
            p.contains("packageinstaller") ||
            p.contains("dialer") ||
            p == "com.android.phone" ||
            p.contains("incallui") ||
            p.contains("telecom") ||
            p.contains("emergency") ||
            p.contains("deskclock") ||
            p.contains("clock")
    }

    override fun onInterrupt() {
        stopYouTubeWarnings()
        handler.removeCallbacks(screenTimeCheck)
    }

    override fun onDestroy() {
        stopYouTubeWarnings()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
