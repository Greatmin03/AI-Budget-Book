package com.example.budget_book

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Dart <-> 네이티브 브리지.
 *
 * - MethodChannel: 권한 확인 / 설정 화면 열기 / 큐 회수
 * - EventChannel : "큐에 새 알림이 있다" 신호 (내용은 보내지 않는다)
 */
object NotificationBridge {

    private const val TAG = "BudgetBookBridge"
    private const val METHOD_CHANNEL = "budget_book/notifications"
    private const val EVENT_CHANNEL = "budget_book/notifications/events"

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext

        MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPermissionGranted" ->
                        result.success(isNotificationAccessGranted(appContext))

                    "openPermissionSettings" -> {
                        openNotificationAccessSettings(appContext)
                        result.success(null)
                    }

                    "isServiceConnected" ->
                        result.success(PaymentNotificationListenerService.isConnected)

                    "drainQueue" -> {
                        try {
                            result.success(NotificationQueueStore.readAndClear(appContext))
                        } catch (e: Exception) {
                            Log.e(TAG, "drainQueue 실패", e)
                            result.error("DRAIN_FAILED", e.message, null)
                        }
                    }

                    "queueSize" ->
                        result.success(NotificationQueueStore.size(appContext))

                    // 알림을 보낸 적이 있는 앱 목록(설정 화면의 후보).
                    "seenSources" ->
                        result.success(
                            NotificationSourceStore.seenSources(appContext)
                        )

                    // 수집 허용 목록을 네이티브 캐시에 복사한다.
                    // 리스너는 Flutter 엔진 없이도 이 값으로 판단한다.
                    "setEnabledSources" -> {
                        val packages =
                            call.argument<List<String>>("packages") ?: emptyList()
                        NotificationSourceStore.setEnabledPackages(
                            appContext,
                            packages,
                        )
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }

        EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    // 구독 시점에 이미 쌓인 것이 있으면 즉시 알려 준다.
                    if (NotificationQueueStore.size(appContext) > 0) {
                        notifyQueueChanged()
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    /**
     * "큐가 변했다" 신호를 Dart 로 보낸다.
     *
     * 알림 콜백은 바인더 스레드에서 오지만 EventSink 는 메인 스레드에서만
     * 건드려야 하므로 [mainHandler] 로 넘긴다.
     */
    fun notifyQueueChanged() {
        mainHandler.post {
            try {
                eventSink?.success(1)
            } catch (e: Exception) {
                Log.w(TAG, "신호 전송 실패", e)
            }
        }
    }

    /**
     * 알림 접근 권한 확인.
     *
     * androidx 의존 없이 시스템 설정 문자열을 직접 확인한다.
     * (`enabled_notification_listeners` 는 "pkg/cls:pkg/cls" 형식)
     */
    private fun isNotificationAccessGranted(context: Context): Boolean {
        val expected = ComponentName(
            context,
            PaymentNotificationListenerService::class.java
        )
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        return enabled.split(':').any { entry ->
            val component = ComponentName.unflattenFromString(entry.trim())
            component != null &&
                component.packageName == expected.packageName &&
                component.className == expected.className
        }
    }

    private fun openNotificationAccessSettings(context: Context) {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            context.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "알림 접근 설정 화면을 열 수 없음", e)
            // 일부 기기에서는 위 인텐트가 없다. 앱 설정 화면으로 폴백.
            try {
                context.startActivity(
                    Intent(Settings.ACTION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (ignored: Exception) {
                Log.e(TAG, "설정 화면 폴백도 실패", ignored)
            }
        }
    }
}
