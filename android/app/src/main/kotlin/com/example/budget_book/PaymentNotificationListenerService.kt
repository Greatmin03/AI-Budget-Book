package com.example.budget_book

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * 결제 알림 수집기.
 *
 * 여기서는 **판별을 거의 하지 않는다.** 값싼 1차 필터만 적용하고
 * (금액 표기 + 결제 키워드) 실제 파싱/분류는 Dart 쪽 파서가 담당한다.
 * 카드사별 문장 규칙을 Kotlin 과 Dart 양쪽에 두면 반드시 어긋나기 때문이다.
 */
class PaymentNotificationListenerService : NotificationListenerService() {

    companion object {
        private const val TAG = "BudgetBookListener"

        /**
         * 시스템이 이 서비스에 바인딩한 상태인지.
         * 설정 화면의 "리스너 서비스: 연결됨" 표시에 사용한다.
         */
        @Volatile
        var isConnected: Boolean = false
            private set

        /**
         * 결제 알림에 반드시 있어야 하는 키워드.
         *
         * Dart 의 파서(`_requiredKeywords`)와 맞춰 둔다. 여기서 걸러 버리면
         * Dart 는 그 알림을 볼 기회조차 없으므로 이쪽이 더 넓어야 한다.
         */
        private val PAYMENT_KEYWORDS =
            listOf(
                "승인", "결제", "출금", "취소", "이체", "지불", "송금", "보냈",
                // 입금은 지출이 아니지만 정산(더치페이) 후보로 쓰이므로 함께 수집한다.
                "입금", "받았"
            )
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        isConnected = true
        Log.i(TAG, "리스너 연결됨")
        NotificationBridge.notifyQueueChanged()
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        isConnected = false
        Log.w(TAG, "리스너 연결 끊김")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val notification = sbn?.notification ?: return
        val extras = notification.extras ?: return
        val packageName = sbn.packageName ?: return

        // 자기 자신의 알림은 무시한다.
        if (packageName == applicationContext.packageName) return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

        val combined = listOfNotNull(title, text, subText, bigText).joinToString(" ")
        if (!looksLikePayment(combined)) return

        // 결제 알림처럼 보이는 앱은 설정 화면에서 고를 수 있도록 기록해 둔다.
        // (수집 대상이 아니어도 "감지된 앱" 으로는 남는다)
        NotificationSourceStore.recordSeen(applicationContext, packageName)

        // 사용자가 고른 앱이 아니면 즉시 버린다. 큐에도 넣지 않는다.
        // 금융 앱을 여러 개 쓰면 같은 결제가 여러 번 들어오기 때문이다.
        if (!NotificationSourceStore.shouldCollect(applicationContext, packageName)) {
            Log.d(TAG, "수집 대상 아님, 무시: $packageName")
            return
        }

        NotificationQueueStore.append(
            context = applicationContext,
            packageName = packageName,
            title = title,
            text = text,
            subText = subText,
            bigText = bigText,
            postedAt = if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis()
        )

        Log.d(TAG, "결제 알림 후보 수집: $packageName / $title")

        // Dart 가 살아 있으면 즉시 회수하도록 신호만 보낸다(내용은 보내지 않는다).
        NotificationBridge.notifyQueueChanged()
    }

    /**
     * 값싼 1차 필터.
     *
     * 금액 표기("원")와 결제 관련 키워드가 함께 있어야 후보로 본다.
     * 카드사별 형식에 의존하지 않으므로 새로운 카드사도 그냥 통과한다.
     */
    private fun looksLikePayment(text: String): Boolean {
        if (text.isBlank()) return false
        if (!text.contains("원")) return false
        if (!PAYMENT_KEYWORDS.any { text.contains(it) }) return false
        // 숫자가 하나도 없으면 금액이 아니다.
        return text.any { it.isDigit() }
    }
}
