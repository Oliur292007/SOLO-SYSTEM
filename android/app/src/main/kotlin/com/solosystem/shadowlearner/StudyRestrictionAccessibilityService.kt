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
    @Volatile private var foregroundWorker = Executors.newSingleThreadExecutor()
    private val usageCheckInFlight = AtomicBoolean(false)
    private val foregroundCheckInFlight = AtomicBoolean(false)

    @Volatile private var currentForegroundPackage: String? = null
    @Volatile private var currentSessionUsageMs = 0L
    @Volatile private var lastUsageTickElapsed = 0L

    private var lastRedirectAt = 0L
    private var lastBlockedPackage: String? = null
    private var currentUsageDay = usageDayKey()
    @Volatile private var youtubeWarningStartedAtElapsed = 0L
    private var youtubeWarningNotificationId = 54_000

    /**
     * Independent background foreground-app polling. Accessibility events remain
     * the immediate path; this UsageStats path catches missed OEM callbacks while
     * the AccessibilityService stays connected in the background.
     */
    private val foregroundPackageCheck = object : Runnable {
        override fun run() {
            if (!isConnected) return
            if (!ScreenTimePolicy.hasUsageAccess(this@StudyRestrictionAccessibilityService)) {
                scheduleForegroundPolling(2_000L)
                return
            }
            if (!foregroundCheckInFlight.compareAndSet(false, true)) {
                scheduleForegroundPolling(500L)
                return
            }

            try {
                foregroundWorker.execute {
                    try {
                        val detectedPackage = readForegroundPackageFromUsageStats()
                        if (detectedPackage != null) {
                            handler.post {
                                if (!isConnected) return@post
                                if (currentForegroundPackage != detectedPackage) {
                                    currentForegroundPackage = detectedPackage
                                    currentSessionUsageMs = 0L
                                    lastUsageTickElapsed = SystemClock.elapsedRealtime()
                                }
                                lastKnownForegroundPackageForTimer = detectedPackage
                                enforceForegroundPackage(detectedPackage)
                            }
                        }
                    } catch (error: Exception) {
                        Log.w("ShadowLearnerAccess", "Background foreground-package poll failed", error)
                    } finally {
                        foregroundCheckInFlight.set(false)
                        handler.post {
                            if (isConnected) scheduleForegroundPolling(1_000L)
                        }
                    }
                }
            } catch (error: RejectedExecutionException) {
                foregroundCheckInFlight.set(false)
                Log.w("ShadowLearnerAccess", "Foreground worker is restarting", error)
                scheduleForegroundPolling(1_000L)
            }
        }
    }

    private fun scheduleForegroundPolling(delayMs: Long = 1_000L) {
        if (!isConnected) return
        handler.removeCallbacks(foregroundPackageCheck)
        handler.postDelayed(foregroundPackageCheck, delayMs)
    }

    /**
     * Resolve the most recent foreground transition from the last 15 seconds.
     * Only package names and event types are read; no app content is inspected.
     */
    private fun readForegroundPackageFromUsageStats(): String? {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE)
            as android.app.usage.UsageStatsManager
        val now = System.currentTimeMillis()
        val events = manager.queryEvents(now - 15_000L, now)
        val event = android.app.usage.UsageEvents.Event()
        var foregroundPackage: String? = null

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            when (event.eventType) {
                android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED,
                android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    foregroundPackage = packageName
                }
                android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED,
                android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    if (foregroundPackage == packageName) {
                        foregroundPackage = null
                    }
                }
            }
        }
        return foregroundPackage
    }

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
                    val emergencyUnlockActive = isEmergencyUnlockActive()
                    val studyActive = isStudyProtectionActive() && !emergencyUnlockActive
                    val penaltyLockActive = isPenaltyLockActive() && !emergencyUnlockActive
                    updateYouTubeWarning(packageName, nowElapsed, studyActive)
                    val today = usageDayKey()

                    if (today != currentUsageDay) {
                        currentUsageDay = today
                        currentSessionUsageMs = 0L
                        lastUsageTickElapsed = nowElapsed
                    }
                    if (lastUsageTickElapsed > 0L && isScreenInteractive()) {
                        currentSessionUsageMs +=
                            (nowElapsed - lastUsageTickElapsed).coerceAtLeast(0L)
                    }
                    lastUsageTickElapsed = nowElapsed

                    // Re-check the already-open foreground app on every watchdog
                    // pass. A schedule can become active while an app is already
                    // foregrounded, without generating a new window-state event.
                    val penaltyAllowed = packageName != null &&
                        ScreenTimePolicy.isPenaltyAllowed(
                            this@StudyRestrictionAccessibilityService,
                            packageName
                        )
                    val penaltyExempt = penaltyLockActive && penaltyAllowed

                    val shouldBlockForPenalty = penaltyLockActive &&
                        packageName != null &&
                        !isSystemAllowedPackage(packageName) &&
                        !penaltyAllowed

                    val shouldBlockForStudy = studyActive &&
                        packageName != null &&
                        !isSystemAllowedPackage(packageName) &&
                        !penaltyExempt &&
                        !ScreenTimePolicy.isStudyAllowed(
                            this@StudyRestrictionAccessibilityService,
                            packageName
                        )

                    var shouldBlock = false
                    if (!emergencyUnlockActive &&
                        packageName != null &&
                        !isSystemAllowedPackage(packageName) &&
                        !penaltyExempt &&
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

                    if ((shouldBlockForPenalty || shouldBlockForStudy || shouldBlock) && packageName != null) {
                        handler.post {
                            if (isConnected &&
                                currentForegroundPackage == packageName
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

        // The interval comes from Supabase config (default: five minutes).
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

    /** Reads the developer-authorized emergency unlock window from Flutter preferences. */
    private fun isEmergencyUnlockActive(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val unlockUntil = prefs.getLong("flutter.emergency_unlock_until_ms", 0L)
        return unlockUntil > System.currentTimeMillis()
    }

    /** Reads the persisted Flutter penalty and Night Lock state using absolute expiry time. */
    private fun isPenaltyLockActive(): Boolean {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val penaltyUntil = prefs.getLong("flutter.penalty_until", 0L)
        val penaltyActive = penaltyUntil > System.currentTimeMillis()
        val nightLockActive = prefs.getBoolean("flutter.night_lock_active", false)
        return penaltyActive || nightLockActive
    }

    /** Keep one watchdog callback only; policy scans run on usageWorker. */
    private fun scheduleMonitoring(delayMs: Long = 0L) {
        if (!isConnected) return
        handler.removeCallbacks(screenTimeCheck)
        handler.postDelayed(screenTimeCheck, delayMs)
    }

    /**
     * When Android reconnects this service while another app is already open,
     * there may be no fresh window event for that app. Recover only the latest
     * foreground package from UsageStats events; no window content is read.
     */
    private fun restoreForegroundPackageFromUsageStats() {
        try {
            usageWorker.execute {
                try {
                    val manager = getSystemService(Context.USAGE_STATS_SERVICE)
                        as android.app.usage.UsageStatsManager
                    val now = System.currentTimeMillis()
                    val events = manager.queryEvents(now - 15_000L, now)
                    val event = android.app.usage.UsageEvents.Event()
                    var foregroundPackage: String? = null

                    while (events.hasNextEvent()) {
                        events.getNextEvent(event)
                        val packageName = event.packageName ?: continue
                        when (event.eventType) {
                            android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED,
                            android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                                foregroundPackage = packageName
                            }
                            android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED,
                            android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                                if (foregroundPackage == packageName) {
                                    foregroundPackage = null
                                }
                            }
                        }
                    }

                    val restoredPackage = foregroundPackage ?: return@execute
                    handler.post {
                        if (!isConnected) return@post
                        currentForegroundPackage = restoredPackage
                        lastKnownForegroundPackageForTimer = restoredPackage
                        currentSessionUsageMs = 0L
                        lastUsageTickElapsed = SystemClock.elapsedRealtime()
                        scheduleMonitoring()
                    }
                } catch (error: Exception) {
                    Log.w(
                        "ShadowLearnerAccess",
                        "Could not restore foreground app after service connection",
                        error
                    )
                }
            }
        } catch (error: RejectedExecutionException) {
            Log.w("ShadowLearnerAccess", "Foreground restore worker unavailable", error)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        if (usageWorker.isShutdown || usageWorker.isTerminated) {
            usageWorker = Executors.newSingleThreadExecutor()
        }
        if (foregroundWorker.isShutdown || foregroundWorker.isTerminated) {
            foregroundWorker = Executors.newSingleThreadExecutor()
        }
        usageCheckInFlight.set(false)
        foregroundCheckInFlight.set(false)
        currentForegroundPackage = null
        lastKnownForegroundPackageForTimer = null
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
        restoreForegroundPackageFromUsageStats()
        scheduleForegroundPolling()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        try {
            if (event == null) return
            if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED
            ) return

            // OEMs may report System UI/overlay as the event package even
            // while a restricted app is the actual foreground window. Prefer
            // the active window package; only its package name is read.
            val foregroundWindowPackage = runCatching {
                rootInActiveWindow?.packageName?.toString()?.takeIf { it.isNotBlank() }
            }.getOrNull()
            val openedPackage = foregroundWindowPackage
                ?: event.packageName?.toString()?.takeIf { it.isNotBlank() }
                ?: return

            if (currentForegroundPackage != openedPackage) {
                currentForegroundPackage = openedPackage
                currentSessionUsageMs = 0L
                lastUsageTickElapsed = SystemClock.elapsedRealtime()
            }
            enforceForegroundPackage(openedPackage)
        } catch (error: Exception) {
            Log.e("ShadowLearnerAccess", "Accessibility event processing failed", error)
        }
    }

    /**
     * Shared enforcement for Accessibility events and background UsageStats polling.
     * PR #17 allowlists and Emergency Unlock are evaluated in one place.
     */
    private fun enforceForegroundPackage(packageName: String) {
        lastKnownForegroundPackageForTimer = packageName
        if (ScreenTimePolicy.categoryFor(this, packageName) != "youtube_special") {
            youtubeWarningStartedAtElapsed = 0L
        }
        if (ScreenTimePolicy.shouldPauseQuestTimerForPackage(this, packageName)) {
            ScreenTimePolicy.pauseRunningQuestTimer(this)
        }

        if (isSystemAllowedPackage(packageName)) return
        if (isEmergencyUnlockActive()) {
            scheduleMonitoring()
            return
        }

        // Penalty and Night Lock take precedence over normal Study Protection exceptions.
        if (isPenaltyLockActive()) {
            if (ScreenTimePolicy.isPenaltyAllowed(this, packageName)) {
                scheduleMonitoring()
            } else {
                redirectHome(packageName)
            }
            return
        }

        if (isStudyProtectionActive()) {
            if (ScreenTimePolicy.isStudyAllowed(this, packageName)) {
                scheduleMonitoring()
            } else {
                redirectHome(packageName)
            }
            return
        }

        if (ScreenTimePolicy.hasUsageAccess(this)) scheduleMonitoring()
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

        // Keep the actual HOME surface available to avoid a redirect loop.
        // This is resolved by Android instead of guessing from package names.
        val isDefaultHomePackage = runCatching {
            val homeIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            packageManager.resolveActivity(
                homeIntent,
                PackageManager.MATCH_DEFAULT_ONLY
            )?.activityInfo?.packageName == packageName
        }.getOrDefault(false)

        // Exact Android component package IDs only. Broad substring checks such
        // as "dialer", "telecom", "emergency", or "clock" can accidentally
        // exempt unrelated third-party apps with similar package names.
        val isCoreAndroidPackage = packageName in setOf(
            "com.android.systemui",
            "com.google.android.systemui",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.android.phone",
            "com.android.server.telecom",
            "com.android.emergency",
            "com.google.android.emergency",
            "com.android.cellbroadcastreceiver",
            "com.google.android.cellbroadcastreceiver"
        )

        val systemFlags = android.content.pm.ApplicationInfo.FLAG_SYSTEM or
            android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP

        // The device's selected dialer is exempt only when Android marks it as a preinstalled
        // or updated system app. A user-installed dialer is not a system bypass.
        val isSystemDefaultDialer = runCatching {
            val telecom = getSystemService(Context.TELECOM_SERVICE)
                as? android.telecom.TelecomManager
            val isSelectedDialer = telecom?.defaultDialerPackage == packageName
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            isSelectedDialer && (appInfo.flags and systemFlags) != 0
        }.getOrDefault(false)

        // Resolve the platform's emergency-assist handler dynamically so OEM system
        // emergency UI remains available without trusting package-name substrings.
        val isSystemEmergencyHandler = runCatching {
            val emergencyIntent = Intent("android.intent.action.EMERGENCY_ASSIST")
            val resolved = packageManager.resolveActivity(
                emergencyIntent,
                PackageManager.MATCH_DEFAULT_ONLY
            )?.activityInfo ?: return@runCatching false
            val isResolvedHandler = resolved.packageName == packageName
            val isSystemHandler = (resolved.applicationInfo.flags and systemFlags) != 0
            isResolvedHandler && isSystemHandler
        }.getOrDefault(false)

        return isDefaultHomePackage || isCoreAndroidPackage ||
            isSystemDefaultDialer || isSystemEmergencyHandler
    }

    override fun onInterrupt() {
        // An interrupt is not a disconnect. Re-arm the watchdog without
        // changing Android's system-managed AccessibilityService lifecycle.
        scheduleMonitoring()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.w("ShadowLearnerAccess", "Accessibility service unbound by Android")
        isConnected = false
        // A reconnect must rediscover the foreground app instead of reusing stale state.
        currentForegroundPackage = null
        lastKnownForegroundPackageForTimer = null
        handler.removeCallbacksAndMessages(null)
        usageWorker.shutdownNow()
        foregroundWorker.shutdownNow()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        Log.w("ShadowLearnerAccess", "Accessibility service destroyed")
        isConnected = false
        currentForegroundPackage = null
        lastKnownForegroundPackageForTimer = null
        handler.removeCallbacksAndMessages(null)
        usageWorker.shutdownNow()
        foregroundWorker.shutdownNow()
        super.onDestroy()
    }
}
