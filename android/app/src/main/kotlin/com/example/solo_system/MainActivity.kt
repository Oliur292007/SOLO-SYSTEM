package com.example.solo_system

import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "solo_system/app_restriction"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setStudyRestriction" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        getSharedPreferences(
                            StudyRestrictionAccessibilityService.PREFS,
                            MODE_PRIVATE
                        ).edit().putBoolean(
                            StudyRestrictionAccessibilityService.KEY_ACTIVE,
                            active
                        ).apply()
                        result.success(true)
                    }
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "isAccessibilityEnabled" -> {
                        val manager = getSystemService(ACCESSIBILITY_SERVICE) as AccessibilityManager
                        val enabled = manager.getEnabledAccessibilityServiceList(
                            AccessibilityManager.FEEDBACK_ALL_MASK
                        ).any {
                            it.resolveInfo.serviceInfo.packageName == packageName &&
                                it.resolveInfo.serviceInfo.name ==
                                StudyRestrictionAccessibilityService::class.java.name
                        }
                        result.success(enabled)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
