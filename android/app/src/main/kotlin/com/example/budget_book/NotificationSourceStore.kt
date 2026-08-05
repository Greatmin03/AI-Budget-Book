package com.example.budget_book

import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.util.Log
import org.json.JSONObject

/**
 * 알림을 보내는 앱 목록과 "수집 허용" 설정을 보관한다.
 *
 * ## 왜 SharedPreferences 인가
 * 허용 목록의 원본(source of truth)은 Dart 쪽 SQLite(`notification_sources`)다.
 * 하지만 리스너 서비스는 Flutter 엔진이 죽어 있을 때도 돌아가므로
 * SQLite 를 읽을 수 없다. 그래서 Dart 가 설정을 바꿀 때마다 이곳에 복사해 두고,
 * 서비스는 이 캐시만 읽어 **즉시 판단**한다.
 *
 * 두 가지를 따로 저장한다.
 *  - 발견된 앱(seen): 사용자가 설정 화면에서 고를 수 있도록 알림을 보낸 앱을 기록
 *  - 허용 목록(enabled): 실제로 수집할 패키지
 */
object NotificationSourceStore {

    private const val TAG = "BudgetBookSources"
    private const val PREFS = "budget_book_notification_sources"
    private const val KEY_SEEN = "seen_sources"
    private const val KEY_ENABLED = "enabled_packages"

    /** 발견 기록 상한. 무한정 늘어나지 않게 한다. */
    private const val MAX_SEEN = 100

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * 알림을 보낸 앱을 기록한다(수집 여부와 무관).
     *
     * 설정 화면의 "최근 감지된 앱" 목록이 여기서 나온다.
     */
    fun recordSeen(context: Context, packageName: String) {
        try {
            val store = prefs(context)
            val json = JSONObject(store.getString(KEY_SEEN, "{}") ?: "{}")

            val existing = json.optJSONObject(packageName)
            val label = existing?.optString("label")?.takeIf { it.isNotEmpty() }
                ?: resolveAppLabel(context, packageName)

            json.put(
                packageName,
                JSONObject().apply {
                    put("label", label)
                    put("lastSeenAt", System.currentTimeMillis())
                    put(
                        "detectedAt",
                        existing?.optLong("detectedAt")?.takeIf { it > 0 }
                            ?: System.currentTimeMillis()
                    )
                }
            )

            trimIfNeeded(json)
            store.edit().putString(KEY_SEEN, json.toString()).apply()
        } catch (e: Exception) {
            Log.w(TAG, "발견 기록 실패: $packageName", e)
        }
    }

    /** 발견된 앱 목록을 Dart 로 넘길 형태로 반환한다. */
    fun seenSources(context: Context): List<Map<String, Any?>> {
        return try {
            val json = JSONObject(prefs(context).getString(KEY_SEEN, "{}") ?: "{}")
            val result = mutableListOf<Map<String, Any?>>()
            for (key in json.keys()) {
                val entry = json.optJSONObject(key) ?: continue
                result.add(
                    mapOf(
                        "packageName" to key,
                        "displayName" to entry.optString("label", key),
                        "lastSeenAt" to entry.optLong("lastSeenAt"),
                        "detectedAt" to entry.optLong("detectedAt")
                    )
                )
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "발견 목록 읽기 실패", e)
            emptyList()
        }
    }

    /** Dart 가 허용 목록을 갱신한다. */
    fun setEnabledPackages(context: Context, packages: List<String>) {
        prefs(context).edit()
            .putStringSet(KEY_ENABLED, packages.toSet())
            .apply()
        Log.i(TAG, "수집 허용 앱 ${packages.size}개 갱신")
    }

    fun enabledPackages(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_ENABLED, emptySet()) ?: emptySet()

    /**
     * 이 패키지의 알림을 수집해야 하는가.
     *
     * 허용 목록이 **비어 있으면 전부 허용**한다.
     * 최초 실행이나 설정 전에는 아무것도 수집되지 않는 편이 더 나쁘기 때문이다.
     * (설정 화면이 "아직 고르지 않았다" 는 것을 사용자에게 알린다)
     */
    fun shouldCollect(context: Context, packageName: String): Boolean {
        val enabled = enabledPackages(context)
        if (enabled.isEmpty()) return true
        return enabled.contains(packageName)
    }

    /** 앱 이름을 사람이 읽는 형태로. 실패하면 패키지명을 쓴다. */
    private fun resolveAppLabel(context: Context, packageName: String): String {
        return try {
            val pm: PackageManager = context.packageManager
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            packageName
        }
    }

    /** 오래 안 보인 항목부터 버린다. */
    private fun trimIfNeeded(json: JSONObject) {
        if (json.length() <= MAX_SEEN) return
        val entries = json.keys().asSequence()
            .mapNotNull { key ->
                json.optJSONObject(key)?.let { key to it.optLong("lastSeenAt") }
            }
            .sortedBy { it.second }
            .toList()

        val removeCount = json.length() - MAX_SEEN
        entries.take(removeCount).forEach { json.remove(it.first) }
    }
}
