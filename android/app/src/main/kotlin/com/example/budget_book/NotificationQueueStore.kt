package com.example.budget_book

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * 수집한 알림을 보관하는 파일 큐 (JSONL: 한 줄 = 알림 1건).
 *
 * ## 왜 파일인가
 * Flutter 엔진은 앱이 백그라운드에서 종료되면 함께 죽는다.
 * 그 동안 발생한 결제 알림을 EventChannel 로 보내면 받을 곳이 없어 유실된다.
 * 그래서 리스너 서비스(별도 프로세스 수명)는 항상 파일에 먼저 쓰고,
 * Dart 는 살아날 때마다 [readAndClear] 로 회수한다.
 *
 * 모든 접근은 [lock] 으로 직렬화한다. 알림 콜백(바인더 스레드)과
 * Dart 의 drainQueue 호출(메인 스레드)이 동시에 들어올 수 있기 때문이다.
 */
object NotificationQueueStore {

    private const val TAG = "BudgetBookQueue"
    private const val FILE_NAME = "pending_notifications.jsonl"

    /** 큐가 무한정 커지지 않도록 상한을 둔다(오래된 것부터 버린다). */
    private const val MAX_ENTRIES = 500

    private val lock = Any()

    private fun file(context: Context) = File(context.filesDir, FILE_NAME)

    /** 알림 한 건을 큐에 추가한다. */
    fun append(
        context: Context,
        packageName: String,
        title: String,
        text: String,
        subText: String?,
        bigText: String?,
        postedAt: Long
    ) {
        val json = JSONObject().apply {
            put("packageName", packageName)
            put("title", title)
            put("text", text)
            put("subText", subText ?: "")
            put("bigText", bigText ?: "")
            put("postedAt", postedAt)
        }

        synchronized(lock) {
            try {
                val target = file(context)
                target.appendText(json.toString() + "\n")
                trimIfNeeded(target)
            } catch (e: Exception) {
                Log.e(TAG, "큐 쓰기 실패", e)
            }
        }
    }

    /**
     * 큐의 모든 항목을 반환하고 큐를 비운다.
     *
     * 읽기와 삭제가 같은 lock 안에서 일어나므로 중복 회수나 누락이 없다.
     */
    fun readAndClear(context: Context): List<Map<String, Any?>> {
        synchronized(lock) {
            val target = file(context)
            if (!target.exists()) return emptyList()

            val result = mutableListOf<Map<String, Any?>>()
            try {
                target.forEachLine { line ->
                    val trimmed = line.trim()
                    if (trimmed.isEmpty()) return@forEachLine
                    try {
                        val json = JSONObject(trimmed)
                        result.add(
                            mapOf(
                                "packageName" to json.optString("packageName"),
                                "title" to json.optString("title"),
                                "text" to json.optString("text"),
                                "subText" to json.optString("subText"),
                                "bigText" to json.optString("bigText"),
                                "postedAt" to json.optLong("postedAt")
                            )
                        )
                    } catch (e: Exception) {
                        // 한 줄이 깨져도 나머지는 살린다.
                        Log.w(TAG, "손상된 큐 항목 무시: $trimmed")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "큐 읽기 실패", e)
            }

            // 회수 후 삭제. 삭제에 실패하면 다음 회수에서 중복이 생길 수 있으나,
            // Dart 쪽 fingerprint 중복 방지가 이를 걸러낸다.
            if (!target.delete()) {
                try {
                    target.writeText("")
                } catch (e: Exception) {
                    Log.e(TAG, "큐 비우기 실패", e)
                }
            }
            return result
        }
    }

    fun size(context: Context): Int = synchronized(lock) {
        val target = file(context)
        if (!target.exists()) return 0
        return try {
            target.readLines().count { it.isNotBlank() }
        } catch (e: Exception) {
            0
        }
    }

    /** 상한을 넘으면 오래된 항목부터 버린다. */
    private fun trimIfNeeded(target: File) {
        try {
            val lines = target.readLines().filter { it.isNotBlank() }
            if (lines.size <= MAX_ENTRIES) return
            val kept = lines.takeLast(MAX_ENTRIES)
            target.writeText(kept.joinToString("\n") + "\n")
            Log.w(TAG, "큐 상한 초과: ${lines.size - kept.size}건 폐기")
        } catch (e: Exception) {
            Log.e(TAG, "큐 정리 실패", e)
        }
    }
}
