package com.solosystem.shadowlearner

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import java.util.TimeZone
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
                    "getDailyUsage" -> result.success(ScreenTimePolicy.dailySummary(this))
                    "hasUsageAccess" -> result.success(ScreenTimePolicy.hasUsageAccess(this))
                    "openUsageAccessSettings" -> {
                        ScreenTimePolicy.openUsageAccessSettings(this)
                        result.success(true)
                    }
                    "syncScreenTimeConfig" -> {
                        ScreenTimePolicy.sync(this, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>())
                        result.success(true)
                    }
                    "getLocalTimeZone" -> result.success(TimeZone.getDefault().id)
                    "openAccessibilitySettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(true)
                    }
                    "openAppNotificationSettings" -> {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    "openAppDetailsSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    }
                    "isAccessibilityServiceConnected" -> result.success(\n                        StudyRestrictionAccessibilityService.isConnected\n                    )\n                    "isAccessibilityEnabled" -> {
                        val serviceComponent = ComponentName(
                            this,
                            StudyRestrictionAccessibilityService::class.java
                        )
                        val expectedId = serviceComponent.flattenToString()
                        val enabledServices = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                        ).orEmpty()
                        val enabledInSecureSettings = enabledServices
                            .split(':')
                            .any { it.equals(expectedId, ignoreCase = true) }
                        val manager = getSystemService(ACCESSIBILITY_SERVICE) as AccessibilityManager
                        val enabledInManager = manager.getEnabledAccessibilityServiceList(
                            AccessibilityServiceInfo.FEEDBACK_ALL_MASK
                        ).any { service ->
                            service.id.equals(expectedId, ignoreCase = true) ||
                                (
                                    service.resolveInfo.serviceInfo.packageName == packageName &&
                                    service.resolveInfo.serviceInfo.name.substringAfterLast('.') ==
                                        StudyRestrictionAccessibilityService::class.java.simpleName
                                )
                        }
                        result.success(enabledInSecureSettings || enabledInManager)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
