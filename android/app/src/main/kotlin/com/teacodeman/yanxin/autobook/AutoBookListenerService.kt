package com.teacodeman.yanxin.autobook

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/** 监听范围的包名白名单（**MVP 仅微信 + 支付宝**，SPEC §3.4 第 ① 层）。 */
object AutoBookPackages {
    const val WECHAT = "com.tencent.mm"
    const val ALIPAY = "com.eg.android.AlipayGphone"
    val WATCHED: Set<String> = setOf(WECHAT, ALIPAY)

    fun isWatched(pkg: String?): Boolean = pkg != null && WATCHED.contains(pkg)
}

/**
 * 通知监听服务（F7.15）。
 *
 * 由**系统**绑定（`BIND_NOTIFICATION_LISTENER_SERVICE`），用户需在「设置 → 通知 → 通知使用权」
 * 里手动打开；**不需要前台服务**（省掉 Android 14 的 FGS 类型申报）。
 *
 * 只做三件事：包名过滤 → 取文案 → 落盘队列 + 更新「识别到 N 笔」提示。
 * **不做金额解析、不碰数据库**（见 AutoBookQueue 注释）。
 *
 * 另：每层判定都往 [AutoBookDiagnostics] 记一笔 —— 这个功能一旦不生效，
 * 用户只看到「没记上」，必须能区分「服务没被绑定 / 没抓到 / 抓到被过滤 / 没 drain」。
 */
class AutoBookListenerService : NotificationListenerService() {

    override fun onCreate() {
        super.onCreate()
        AutoBookDiagnostics.load(this)
    }

    /** 系统把服务绑上了（此后 `onNotificationPosted` 才会来）。 */
    override fun onListenerConnected() {
        super.onListenerConnected()
        AutoBookDiagnostics.noteConnected(this, true)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        AutoBookDiagnostics.noteConnected(this, false)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (!AutoBookPackages.isWatched(sbn.packageName)) {
            AutoBookDiagnostics.noteSkippedNotWatched()
            return
        }

        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()
        // 三个正文位全空的（如纯进度通知）没有解析价值
        if (title.isEmpty() && text.isEmpty() && bigText.isEmpty()) {
            AutoBookDiagnostics.noteSkippedEmpty()
            return
        }

        val added = AutoBookQueue.enqueueNotification(
            this,
            sbn.packageName,
            title,
            text,
            bigText,
            subText,
            sbn.postTime,
        )
        if (added) {
            AutoBookDiagnostics.noteCapture(this, sbn.packageName)
            AutoBookNotifier.showPending(this, AutoBookQueue.pendingCount(this))
        } else {
            AutoBookDiagnostics.noteSkippedDedup()
        }
    }
}
