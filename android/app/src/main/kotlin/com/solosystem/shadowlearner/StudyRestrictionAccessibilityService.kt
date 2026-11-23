package com.solosystem.shadowlearner

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent

/**
 * Enforces two independent policies:
 * - Study Protection has priority and blocks every non-system app while active.
 * - Daily Screen Time category limits apply only outside Study Protection.
 * Screen Time categories and whitelist entries never bypass Study Protection.
 */
class StudyRestrictionAccessibilityService : AccessibilityService() {
    companion object {
        const val PREFS = "solo_system_study_restriction"
        const val KEY_ACTIVE = "study_restriction_active"

        @Volatile
        var isConnected: Boolean = false
            private set
    }

    private val handler = Handler(Looper.getMainLooper())
    private var lastRedirectAt = 0L
    private var lastBlockedPackage: String? = null
    private var currentForegroundPackage: String? = null
    private var currentSessionUsageMs = 0L
    private var lastUsageTickElapsed = 0L
    private var currentUsageDay = usageDayKey()

    private val screenTimeCheck = object : Runnable {
        override fun run() {
            try {
                val packageName = currentForegroundPackage
                val nowElapsed = SystemClock.elapsedRealtime()
                val studyActive = getSharedPreferences(PREFS, MODE_PRIVATE)
                    .getBoolean(KEY_ACTIVE, false) || getSharedPreferences(PREFS, MODE_PRIVATE)
                    .getBoolean(ScheduledStudyProtectionReceiver.KEY_SCHEDULE_ACTIVE, false)
                val today = usageDayKey()
                if (today != currentUsageDay) {
                    currentUsageDay = today
                    currentSessionUsageMs = if (
                        packageName != null &&
                        !studyActive &&
                        ScreenTimePolicy.hasUsageAccess(this@StudyRestrictionAccessibilityService)
                    ) {
                        ScreenTimePolicy.usageByPackage(this@StudyRestrictionAccessibilityService)[packageName] ?: 0L
                    } else {
                        0L
                    }
                    lastUsageTickElapsed = nowElapsed
                }
                if (lastUsageTickElapsed > 0L && isScreenInteractive()) {
                    currentSessionUsageMs += (nowElapsed - lastUsageTickElapsed).coerceAtLeast(0L)
                }
                lastUsageTickElapsed = nowElapsed

                // Study Protection always takes precedence over daily Screen Time.
                // Never consult Screen Time categories or whitelist while it is active.
                if (packageName != null && studyActive && !isSystemAllowedPackage(packageName)) {
                    redirectHome(packageName)
                } else if (packageName != null &&
                    !studyActive &&
                    ScreenTimePolicy.hasUsageAccess(this@StudyRestrictionAccessibilityService) &&
                    !isSystemAllowedPackage(packageName)
                ) {
                    val usage = ScreenTimePolicy.usageByPackage(
                        this@StudyRestrictionAccessibilityService
                    )
                    val reportedUsage = usage[packageName] ?: 0L
                    val estimatedUsage = maxOf(reportedUsage, currentSessionUsageMs)
                    if (ScreenTimePolicy.limitReachedForUsage(
                            this@StudyRestrictionAccessibilityService,
                            packageName,
                            estimatedUsage,
                            usage
                        )
                    ) {
                        redirectHome(packageName)
                    }
                }
            } catch (error: Exception) {
                // A failed usage query must not permanently kill the monitoring loop.
                Log.e("ShadowLearnerAccess", "Policy monitoring tick failed", error)
            } finally {
                scheduleMonitoring(10_000L)
            }
        }
    }

    /**
     * Keep one watchdog callback only. The AccessibilityService is system-bound;
     * this loop supplements event callbacks and must never own service lifetime.
     */
    private fun scheduleMonitoring(delayMs: Long = 0L) {
        if (!isConnected) return
        handler.removeCallbacks(screenTimeCheck)
        handler.postDelayed(screenTimeCheck, delayMs)
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
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

            val studyProtectionActive = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getBoolean(KEY_ACTIVE, false)

            if (currentForegroundPackage != openedPackage) {
                currentForegroundPackage = openedPackage
                // Do not perform a full UsageStats event-history scan for every
                // foreground event while Study Protection is active. That scan is
                // only needed by the independent Screen Time policy.
                currentSessionUsageMs = if (
                    !studyProtectionActive &&
                    ScreenTimePolicy.hasUsageAccess(this)
                ) {
                    ScreenTimePolicy.usageByPackage(this)[openedPackage] ?: 0L
                } else {
                    0L
                }
                lastUsageTickElapsed = SystemClock.elapsedRealtime()
            }

            if (isSystemAllowedPackage(openedPackage)) return

            // Study Protection is a global app lock. It takes priority over all
            // Screen Time categories, limits, and approved-app lists.
            if (studyProtectionActive) {
                redirectHome(openedPackage)
                return
            }

            // Daily category limits run independently when Study Protection is off.
            if (ScreenTimePolicy.hasUsageAccess(this) &&
                ScreenTimePolicy.isLimitReached(this, openedPackage)
            ) {
                redirectHome(openedPackage)
            }
        } catch (error: Exception) {
            // An isolated event-processing error must not crash the Accessibility service.
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
        // Android may interrupt accessibility feedback without disconnecting
        // the service. Keep policy monitoring alive instead of cancelling it.
        // onInterrupt is not a disconnect. Re-arm the single monitoring callback
        // without changing the system-managed AccessibilityService lifecycle.
        scheduleMonitoring()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.w("ShadowLearnerAccess", "Accessibility service unbound by Android")
        isConnected = false
        handler.removeCallbacks(screenTimeCheck)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        Log.w("ShadowLearnerAccess", "Accessibility service destroyed")
        isConnected = false
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
