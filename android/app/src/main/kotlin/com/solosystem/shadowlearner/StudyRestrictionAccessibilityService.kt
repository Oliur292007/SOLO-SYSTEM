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
