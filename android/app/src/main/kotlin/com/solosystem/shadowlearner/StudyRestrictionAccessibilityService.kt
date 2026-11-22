package com.solosystem.shadowlearner

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

/**
 * Foreground app guard for active Shadow Learner study sessions.
 * Android does not expose a supported API for force-stopping other apps;
 * this service sends the user back to Home when a non-exempt app opens.
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
        lastRedirectAt = 0L
        lastBlockedPackage = null
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return
        if (!getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(KEY_ACTIVE, false)) return
        val openedPackage = event.packageName?.toString() ?: return
        if (isAllowedPackage(openedPackage)) return
        val now = System.currentTimeMillis()
        if (openedPackage == lastBlockedPackage && now - lastRedirectAt < 900L) return
        if (now - lastRedirectAt < 450L) return
        lastBlockedPackage = openedPackage
        lastRedirectAt = now
        performGlobalAction(GLOBAL_ACTION_HOME)
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
