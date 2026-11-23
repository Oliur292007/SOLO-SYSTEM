package com.solosystem.shadowlearner

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.pm.ApplicationInfo
import android.app.KeyguardManager
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import org.json.JSONObject
import java.util.Calendar

/**
 * Shared policy and UsageStats helpers for the daily Screen Time feature.
 * Categories from Supabase override Android's automatic package classification.
 */
object ScreenTimePolicy {
    const val PREFS = "solo_screen_time_policy"
    private const val KEY_OVERRIDES = "category_overrides"
    private const val KEY_ALLOWED = "study_allowed_packages"
    private const val KEY_SOCIAL_LIMIT = "social_limit_minutes"
    private const val KEY_GAME_LIMIT = "game_limit_minutes"
    private const val KEY_YOUTUBE_WARNING = "youtube_warning_minutes"

    fun hasUsageAccess(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun openUsageAccessSettings(context: Context) {
        context.startActivity(
            android.content.Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                .addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }

    fun sync(context: Context, args: Map<*, *>) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val overrides = args["overrides"] as? Map<*, *> ?: emptyMap<Any, Any>()
        val overrideJson = JSONObject()
        overrides.forEach { (key, value) ->
            if (key is String && value is String) overrideJson.put(key, value)
        }
        val allowed = (args["allowedPackages"] as? List<*>)
            ?.filterIsInstance<String>()
            ?.toSet() ?: emptySet()
        prefs.edit()
            .putString(KEY_OVERRIDES, overrideJson.toString())
            .putStringSet(KEY_ALLOWED, allowed)
            .putInt(KEY_SOCIAL_LIMIT, (args["socialLimitMinutes"] as? Number)?.toInt() ?: 240)
            .putInt(KEY_GAME_LIMIT, (args["gameLimitMinutes"] as? Number)?.toInt() ?: 120)
            .putInt(KEY_YOUTUBE_WARNING, (args["youtubeWarningIntervalMinutes"] as? Number)?.toInt() ?: 5)
            .apply()
    }

    fun socialLimitMinutes(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_SOCIAL_LIMIT, 240).coerceAtLeast(1)

    fun gameLimitMinutes(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_GAME_LIMIT, 120).coerceAtLeast(1)

    fun youtubeWarningMinutes(context: Context): Int =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getInt(KEY_YOUTUBE_WARNING, 5).coerceAtLeast(1)

    /**
     * Decide whether leaving Shadow Learner should pause the Quest Timer.
     * Education apps and YouTube are intentional study destinations. Screen-off
     * and keyguard states are not treated as leaving for another app.
     */
    fun shouldPauseQuestTimer(context: Context): Boolean {
        if (!isScreenInteractiveAndUnlocked(context)) return false
        val foregroundPackage = StudyRestrictionAccessibilityService.lastKnownForegroundPackageForTimer
            ?: mostRecentForegroundPackage(context)
            ?: return true
        return shouldPauseQuestTimerForPackage(context, foregroundPackage)
    }

    fun shouldPauseQuestTimerForPackage(context: Context, packageName: String): Boolean {
        if (!isScreenInteractiveAndUnlocked(context)) return false
        if (packageName == context.packageName) return false

        // System UI overlays (notification shade / quick settings) are not an
        // intentional app switch. The home launcher is deliberately not exempt.
        val normalized = packageName.lowercase()
        if (normalized == "android" || normalized.contains("systemui") ||
            normalized.contains("permissioncontroller")) return false

        val category = categoryFor(context, packageName)
        return category != "education" && category != "youtube_special"
    }

    private fun isScreenInteractiveAndUnlocked(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!power.isInteractive) return false
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return !keyguard.isKeyguardLocked
    }
    /**
     * Persist a pause directly to Flutter's preferences as a process-death
     * fallback. The Flutter lifecycle callback also pauses the in-memory timer.
     */
    fun pauseRunningQuestTimer(context: Context) {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )
        if (!prefs.getBoolean("flutter.timer_running", false)) return
        if (prefs.getString("flutter.timer_quest_id", null).isNullOrBlank()) return

        val endTime = prefs.getLong("flutter.timer_end_time", 0L)
        val remaining = if (endTime > 0L) {
            kotlin.math.ceil((endTime - System.currentTimeMillis()) / 1000.0)
                .toInt().coerceAtLeast(0)
        } else {
            prefs.getInt("flutter.timer_remaining", 0).coerceAtLeast(0)
        }
        prefs.edit()
            .putInt("flutter.timer_remaining", remaining)
            .putBoolean("flutter.timer_running", false)
            .putBoolean("flutter.timer_finished", remaining == 0)
            .remove("flutter.timer_end_time")
            .commit()
    }
    private fun mostRecentForegroundPackage(context: Context): String? {
        if (!hasUsageAccess(context)) return null
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        return runCatching {
            val events = manager.queryEvents(now - 15_000L, now)
            val event = android.app.usage.UsageEvents.Event()
            var latestPackage: String? = null
            var latestTimestamp = 0L
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val isForeground = event.eventType ==
                    android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED ||
                    event.eventType ==
                    android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND
                if (isForeground && event.timeStamp >= latestTimestamp) {
                    latestTimestamp = event.timeStamp
                    latestPackage = event.packageName
                }
            }
            latestPackage
        }.getOrNull()
    }
    fun isStudyAllowed(context: Context, packageName: String): Boolean {
        if (packageName == context.packageName) return true
        val allowed = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getStringSet(KEY_ALLOWED, emptySet()) ?: emptySet()
        return packageName in allowed || categoryFor(context, packageName) == "education" ||
            categoryFor(context, packageName) == "youtube_special"
    }

    fun categoryFor(context: Context, packageName: String): String {
        if (packageName == "com.google.android.youtube" ||
            packageName.contains("youtube", ignoreCase = true)
        ) return "youtube_special"

        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val overrides = runCatching {
            JSONObject(prefs.getString(KEY_OVERRIDES, "{}") ?: "{}")
        }.getOrDefault(JSONObject())
        val override = overrides.optString(packageName, "")
        if (override in setOf("social_media", "game", "education", "excluded")) {
            return override
        }

        val lower = packageName.lowercase()
        if (lower in SOCIAL_PACKAGES || SOCIAL_PACKAGES.any { lower.contains(it) }) {
            return "social_media"
        }
        if (isEducationName(lower)) return "education"
        if (lower in KNOWN_GAME_PACKAGES) return "game"

        val appInfo = runCatching {
            context.packageManager.getApplicationInfo(packageName, 0)
        }.getOrNull()
        if (appInfo != null && android.os.Build.VERSION.SDK_INT >= 26) {
            if (appInfo.category == ApplicationInfo.CATEGORY_GAME) return "game"
            if (appInfo.category == ApplicationInfo.CATEGORY_SOCIAL) return "social_media"
        }

        if (appInfo != null) {
            val label = runCatching {
                context.packageManager.getApplicationLabel(appInfo).toString().lowercase()
            }.getOrDefault("")
            if (isEducationName(label)) return "education"
            if (label.contains("game") || label.contains("games") ||
                listOf("pubg", "free fire", "minecraft", "roblox", "clash", "subway surfers")
                    .any { label.contains(it) }
            ) return "game"
            if (isSocialName(label)) return "social_media"
        }
        return "other"
    }

    private fun isEducationName(value: String): Boolean {
        val terms = listOf(
            "udvash", "unmesh", "shikho", "10minuteschool", "khanacademy",
            "coursera", "edx", "classroom", "education", "learning",
            "study", "school", "byjus", "quizlet", "duolingo"
        )
        return terms.any { value.contains(it) }
    }

    private fun isSocialName(value: String): Boolean {
        val terms = listOf(
            "facebook", "instagram", "tiktok", "twitter", "snapchat",
            "reddit", "pinterest", "discord", "telegram", "whatsapp"
        )
        return terms.any { value.contains(it) }
    }

    private val SOCIAL_PACKAGES = setOf(
        "com.facebook.katana", "com.facebook.orca", "com.instagram.android",
        "com.zhiliaoapp.musically", "com.ss.android.ugc.trill",
        "com.twitter.android", "com.x.android", "com.snapchat.android",
        "com.reddit.frontpage", "com.pinterest", "com.linkedin.android",
        "org.telegram.messenger", "com.whatsapp", "com.discord"
    )

    private val KNOWN_GAME_PACKAGES = setOf(
        "com.dts.freefireth", "com.dts.freefiremax", "com.tencent.ig",
        "com.pubg.imobile", "com.mojang.minecraftpe", "com.roblox.client",
        "com.supercell.clashofclans", "com.supercell.clashroyale",
        "com.kiloo.subwaysurf", "com.king.candycrushsaga",
        "com.mobile.legends"
    )

    fun usageByPackage(context: Context): Map<String, Long> {
        if (!hasUsageAccess(context)) return emptyMap()
        val manager = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now = System.currentTimeMillis()
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        return runCatching {
            val events = manager.queryEvents(start - 24L * 60L * 60L * 1000L, now)
            val event = android.app.usage.UsageEvents.Event()
            val activeSince = mutableMapOf<String, Long>()
            val totals = mutableMapOf<String, Long>()

            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                val packageName = event.packageName ?: continue
                when (event.eventType) {
                    android.app.usage.UsageEvents.Event.ACTIVITY_RESUMED,
                    android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                        // Keep the first open foreground timestamp until the matching
                        // background event; duplicate foreground events must not reset it.
                        if (!activeSince.containsKey(packageName)) {
                            activeSince[packageName] = event.timeStamp
                        }
                    }
                    android.app.usage.UsageEvents.Event.ACTIVITY_PAUSED,
                    android.app.usage.UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                        val foregroundStart = activeSince.remove(packageName)
                        if (foregroundStart != null) {
                            // Clip the session to today's local window. A session that
                            // ended before midnight contributes exactly zero, never negative.
                            val clippedStart = maxOf(foregroundStart, start)
                            val clippedEnd = minOf(event.timeStamp, now)
                            if (clippedEnd > clippedStart) {
                                totals[packageName] = (totals[packageName] ?: 0L) +
                                    (clippedEnd - clippedStart)
                            }
                        }
                    }
                }
            }

            activeSince.forEach { (packageName, foregroundStart) ->
                val clippedStart = maxOf(foregroundStart, start)
                val clippedEnd = now
                if (clippedEnd > clippedStart) {
                    totals[packageName] = (totals[packageName] ?: 0L) +
                        (clippedEnd - clippedStart)
                }
            }
            totals
        }.getOrDefault(emptyMap())
    }

    fun dailySummary(context: Context): Map<String, Any> {
        val usage = usageByPackage(context)
        val apps = runCatching {
            context.packageManager.getInstalledApplications(0)
                .filter { context.packageManager.getLaunchIntentForPackage(it.packageName) != null }
                .map { info ->
                    val name = context.packageManager.getApplicationLabel(info).toString()
                    val category = categoryFor(context, info.packageName)
                    mapOf(
                        "packageName" to info.packageName,
                        "appName" to name,
                        "category" to category,
                        "usageMs" to (usage[info.packageName] ?: 0L)
                    )
                }
                .filter {
                    it["category"] == "social_media" ||
                        it["category"] == "game" ||
                        it["category"] == "education"
                }
                .sortedByDescending { it["usageMs"] as Long }
        }.getOrDefault(emptyList())
        val socialMs = apps.filter { it["category"] == "social_media" }
            .sumOf { it["usageMs"] as Long }
        val gameMs = apps.filter { it["category"] == "game" }
            .sumOf { it["usageMs"] as Long }
        return mapOf(
            "hasUsageAccess" to hasUsageAccess(context),
            "socialMediaMs" to socialMs,
            "gamesMs" to gameMs,
            "socialLimitMinutes" to socialLimitMinutes(context),
            "gameLimitMinutes" to gameLimitMinutes(context),
            "apps" to apps
        )
    }

    /**
     * Limits apply to the whole category, not separately to each app.
     * estimatedCurrentPackageUsageMs lets the accessibility service include
     * the current foreground session before UsageStatsManager publishes it.
     */
    fun limitReachedForUsage(
        context: Context,
        packageName: String,
        estimatedCurrentPackageUsageMs: Long,
        usage: Map<String, Long> = usageByPackage(context)
    ): Boolean {
        val category = categoryFor(context, packageName)
        val limitMinutes = when (category) {
            "social_media" -> socialLimitMinutes(context)
            "game" -> gameLimitMinutes(context)
            else -> return false
        }
        val categoryUsageMs = usage.entries
            .filter { categoryFor(context, it.key) == category }
            .sumOf { it.value }
        val reportedCurrentUsageMs = usage[packageName] ?: 0L
        val unreportedCurrentSessionMs =
            (estimatedCurrentPackageUsageMs - reportedCurrentUsageMs).coerceAtLeast(0L)
        return categoryUsageMs + unreportedCurrentSessionMs >= limitMinutes * 60_000L
    }

    fun isLimitReached(context: Context, packageName: String): Boolean {
        val usage = usageByPackage(context)
        return limitReachedForUsage(
            context,
            packageName,
            usage[packageName] ?: 0L,
            usage
        )
    }
}
