package com.solosystem.shadowlearner

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
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
            handler.postDelayed(this, 10_000L)
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        isConnected = true
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
        handler.removeCallbacks(screenTimeCheck)
    }

    override fun onUnbind(intent: Intent?): Boolean {
        isConnected = false
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        isConnected = false
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }
}
