package com.solosystem.shadowlearner

import android.accessibilityservice.AccessibilityService
import android.Manifest
import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Enforces Study Protection and daily Screen Time policies.
 *
 * Accessibility callbacks stay lightweight. UsageStats history scans are
 * performed on a dedicated worker because they can be expensive and must not
 * block Android's AccessibilityService main thread (which can trigger ANRs and
 * cause Android to mark the service as malfunctioning).
 */
class StudyRestrictionAccessibilityService : AccessibilityService() {
    companion object {
        const val PREFS = "solo_system_study_restriction"
        const val KEY_ACTIVE = "study_restriction_active"
        private const val YOUTUBE_WARNING_CHANNEL = "youtube_time_reminders"

        @Volatile
        var isConnected: Boolean = false
            private set

        @Volatile
        var lastKnownForegroundPackageForTimer: String? = null
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var usageWorker = Executors.newSingleThreadExecutor()
    private val usageCheckInFlight = AtomicBoolean(false)

    @Volatile private var currentForegroundPackage: String? = null
    @Volatile private var currentSessionUsageMs = 0L
    @Volatile private var lastUsageTickElapsed = 0L

    private var lastRedirectAt = 0L
    private var lastBlockedPackage: String? = null
    private var currentUsageDay = usageDayKey()
    @Volatile private var youtubeWarningStartedAtElapsed = 0L
    private var youtubeWarningNotificationId = 54_000

    private val screenTimeCheck = object : Runnable {
        override fun run() {
            if (!isConnected) return
            if (!usageCheckInFlight.compareAndSet(false, true)) {
                scheduleMonitoring(10_000L)
                return
            }

            val packageName = currentForegroundPackage
            try {
                usageWorker.execute {
                    try {
                    val nowElapsed = SystemClock.elapsedRealtime()
                    val studyActive = isStudyProtectionActive()
                    updateYouTubeWarning(packageName, nowElapsed, studyActive)
                    val today = usageDayKey()

                    if (today != currentUsageDay) {
                        currentUsageDay = today
                        currentSessionUsageMs = 0L
                        lastUsageTickElapsed = nowElapsed
                    }
                    if (lastUsageTickElapsed > 0L && isScreenInteractive() && !studyActive) {
                        currentSessionUsageMs +=
                            (nowElapsed - lastUsageTickElapsed).coerceAtLeast(0L)
                    }
                    lastUsageTickElapsed = nowElapsed

                    var shouldBlock = false
                    if (packageName != null &&
                        !studyActive &&
                        !isSystemAllowedPackage(packageName) &&
                        ScreenTimePolicy.hasUsageAccess(this@StudyRestrictionAccessibilityService)
                    ) {
                        val usage = ScreenTimePolicy.usageByPackage(
                            this@StudyRestrictionAccessibilityService
                        )
                        val reportedUsage = usage[packageName] ?: 0L
                        val estimatedUsage = maxOf(reportedUsage, currentSessionUsageMs)
                        shouldBlock = ScreenTimePolicy.limitReachedForUsage(
                            this@StudyRestrictionAccessibilityService,
                            packageName,
                            estimatedUsage,
                            usage
                        )
                    }

                    if (shouldBlock && packageName != null) {
                        handler.post {
                            if (isConnected &&
                                currentForegroundPackage == packageName &&
                                !isStudyProtectionActive()
                            ) {
                                redirectHome(packageName)
                            }
                        }
                    }
                } catch (error: Exception) {
                    Log.e("ShadowLearnerAccess", "Background policy check failed", error)
                } finally {
                    usageCheckInFlight.set(false)
                    handler.post {
                        if (isConnected) scheduleMonitoring(10_000L)
                    }
                    }
                }
            } catch (error: RejectedExecutionException) {
                usageCheckInFlight.set(false)
                Log.w("ShadowLearnerAccess", "Usage worker is restarting", error)
                scheduleMonitoring(1_000L)
            }
        }
    }

    private fun updateYouTubeWarning(
        packageName: String?,
        nowElapsed: Long,
        studyActive: Boolean
    ) {
        val keyguard = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        val isYouTubeForeground = packageName != null &&
            ScreenTimePolicy.categoryFor(this, packageName) == "youtube_special"
        if (!studyActive || !isYouTubeForeground || !isScreenInteractive() ||
            keyguard.isKeyguardLocked) {
            youtubeWarningStartedAtElapsed = 0L
            return
        }

        if (youtubeWarningStartedAtElapsed == 0L) {
            youtubeWarningStartedAtElapsed = nowElapsed
            return
        }

        val intervalMinutes = ScreenTimePolicy.youtubeWarningMinutes(this)
        val intervalMs = intervalMinutes * 60_000L
        if (nowElapsed - youtubeWarningStartedAtElapsed >= intervalMs) {
            postYouTubeWarning(intervalMinutes)
            youtubeWarningStartedAtElapsed = nowElapsed
        }
    }

    private fun postYouTubeWarning(intervalMinutes: Int) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                PackageManager.PERMISSION_GRANTED) return

        try {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (Build.VERSION.SDK_INT >= 26) {
                val channel = NotificationChannel(
                    YOUTUBE_WARNING_CHANNEL,
                    "YouTube time reminders",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Periodic reminders while YouTube is open during Study Protection."
                }
                manager.createNotificationChannel(channel)
            }

            val builder = if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, YOUTUBE_WARNING_CHANNEL)
            } else {
                Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
            }
            val notification = builder
                .setSmallIcon(applicationInfo.icon)
                .setContentTitle("YOUTUBE TIME CHECK")
                .setContentText("$intervalMinutes minutes have passed on YouTube. Stay focused on your learning goal.")
                .setCategory(Notification.CATEGORY_REMINDER)
                .setAutoCancel(true)
                .build()
            manager.notify(youtubeWarningNotificationId++, notification)
        } catch (error: Exception) {
            Log.w("ShadowLearnerAccess", "Could not post YouTube reminder", error)
        }
    }

    private fun isStudyProtectionActive(): Boolean {
        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        return prefs.getBoolean(KEY_ACTIVE, false) ||
            prefs.getBoolean(ScheduledStudyProtectionReceiver.KEY_SCHEDULE_ACTIVE, false)
    }

    /** Keep one watchdog callback only; policy scans run on usageWorker. */
    private fun scheduleMonitoring(delayMs: Long = 0L) {
        if (!isConnected) return
        handler.removeCallbacks(screenTimeCheck)
        handler.postDelayed(screenTimeCheck, delayMs)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        if (usageWorker.isShutdown || usageWorker.isTerminated) {
            usageWorker = Executors.newSingleThreadExecutor()
        }
        usageCheckInFlight.set(false)
        currentForegroundPackage = runCatching {
            rootInActiveWindow?.packageName?.toString()?.takeIf { it.isNotBlank() }
        }.getOrNull()
        lastKnownForegroundPackageForTimer = currentForegroundPackage
        lastUsageTickElapsed = SystemClock.elapsedRealtime()
        isConnected = true
        Log.i("ShadowLearnerAccess", "Accessibility service connected")
        serviceInfo = serviceInfo.apply {
            eventTypes =
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOWS_CHANGED
            notificationTimeout = 80L
        }
        lastRedirectAt = 0L
        lastBlockedPackage = null
        scheduleMonitoring()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            if (event == null) return
            if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
            ) return

            val foregroundPackage = rootInActiveWindow?.packageName?.toString()
                ?.takeIf { it.isNotBlank() }
            val openedPackage = foregroundPackage
                ?: event.packageName?.toString()?.takeIf { it.isNotBlank() }
                ?: return

            lastKnownForegroundPackageForTimer = openedPackage
            if (ScreenTimePolicy.categoryFor(this, openedPackage) != "youtube_special") {
                youtubeWarningStartedAtElapsed = 0L
            }
            if (ScreenTimePolicy.shouldPauseQuestTimerForPackage(this, openedPackage)) {
                ScreenTimePolicy.pauseRunningQuestTimer(this)
            }
            if (currentForegroundPackage != openedPackage) {
                currentForegroundPackage = openedPackage
                // Do not query the complete UsageStats event history on Android's
                // Accessibility callback thread. The worker handles that separately.
                currentSessionUsageMs = 0L
                lastUsageTickElapsed = SystemClock.elapsedRealtime()
            }

            if (isSystemAllowedPackage(openedPackage)) return

            // Study Protection is time-critical and uses only a SharedPreferences
            // read here; it never waits for the UsageStats worker.
            if (isStudyProtectionActive()) {
                // Education / YouTube-special and explicitly allowed packages
                // remain available during Study Protection.
                if (ScreenTimePolicy.isStudyAllowed(this, openedPackage)) return
                redirectHome(openedPackage)
                return
            }

            // Screen Time evaluation is asynchronous and cannot block accessibility.
            if (ScreenTimePolicy.hasUsageAccess(this)) {
                scheduleMonitoring()
            }
        } catch (error: Exception) {
            Log.e("ShadowLearnerAccess", "Accessibility event processing failed", error)
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
        // An interrupt is not a disconnect. Re-arm the watchdog without
        // changing Android's system-managed AccessibilityService lifecycle.
        scheduleMonitoring()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.w("ShadowLearnerAccess", "Accessibility service unbound by Android")
        isConnected = false
        handler.removeCallbacksAndMessages(null)
        usageWorker.shutdownNow()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        Log.w("ShadowLearnerAccess", "Accessibility service destroyed")
        isConnected = false
        handler.removeCallbacksAndMessages(null)
        usageWorker.shutdownNow()
        super.onDestroy()
    }
}
