package com.solosystem.shadowlearner

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * Foreground app guard for active Shadow Learner study sessions.
 * Android does not expose a supported API for force-stopping other apps;
 * this service returns the user to Home when a non-exempt app opens.
 */
class StudyRestrictionAccessibilityService : AccessibilityService() {
    companion object {
        const val PREFS = "solo_system_study_restriction"
        const val KEY_ACTIVE = "study_restriction_active"
    }

    private var lastRedirectAt = 0L
    private var lastBlockedPackage: String? = null

    override fun onServiceConnected() {
        super.onServiceConnected()

        // Apply the event configuration at runtime as well as in XML. This
        // helps OEM Android builds that do not consistently apply XML options.
        serviceInfo = serviceInfo.apply {
            eventTypes =
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                AccessibilityEvent.TYPE_WINDOWS_CHANGED
            notificationTimeout = 80L
        }

        lastRedirectAt = 0L
        lastBlockedPackage = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
            event.eventType != AccessibilityEvent.TYPE_WINDOWS_CHANGED) return

        val restrictionActive = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getBoolean(KEY_ACTIVE, false)
        if (!restrictionActive) return

        // Some launchers/OEMs send a window event without packageName.
        val openedPackage = event.packageName?.toString()
            ?: rootInActiveWindow?.packageName?.toString()
            ?: return

        if (isAllowedPackage(openedPackage)) return

        val now = System.currentTimeMillis()
        if (openedPackage == lastBlockedPackage && now - lastRedirectAt < 900L) return
        if (now - lastRedirectAt < 450L) return

        lastBlockedPackage = openedPackage
        lastRedirectAt = now

        val movedHome = performGlobalAction(GLOBAL_ACTION_HOME)
        if (!movedHome) {
            // Fallback for OEM builds where GLOBAL_ACTION_HOME returns false.
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

    private fun isAllowedPackage(packageName: String): Boolean {
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

    override fun onInterrupt() {}
}
