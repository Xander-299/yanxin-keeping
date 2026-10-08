package com.teacodeman.yanxin.autobook

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

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
 * 另：每层判定都往 [AutoBookDiagnostics] 记一笔 + `Log` 一行 —— 这个功能一旦不生效，
 * 用户只看到「没记上」，必须能区分「服务没被绑定 / 没抓到 / 抓到被过滤 / 没 drain」。
 *
 * ## 补抓（catch-up）为什么是必需的（2026-10-08 Redmi K50 事故）
 *
 * `onNotificationPosted` 是**推送**式回调：**通知在服务未连接期间发布，系统不会在连上后补发**。
 * 真机实测：支付宝付款通知 22:29:37 发布，本服务 22:31:28 才被系统连上 → 那笔支付
 * **永久丢失**，而 App 界面上完全看不出来（诊断只显示「最近捕获：从未」）。
 *
 * 所以连接成功时、以及 App 每次回到前台时（Dart 侧 `catchUp` 通道调用，必须在 drain 之前），
 * 都主动 `getActiveNotifications()` 把**通知栏里仍存在的**通知过一遍。
 * 去重交给 [AutoBookSeen]（持久指纹），所以重复补抓不会重复入队。
 */
class AutoBookListenerService : NotificationListenerService() {

    /** 单条通知的处理结论（同时用于日志与诊断）。 */
    enum class Decision { NOT_WATCHED, EMPTY, GROUP_SUMMARY, DEDUP, CAPTURED }

    companion object {
        private const val TAG = "AutoBookListener"

        /** 补抓只认 24 小时内的通知 —— 更早的多半是过期的营销推送，捞回来只会污染账本。 */
        private const val CATCH_UP_MAX_AGE_MS = 24L * 60 * 60 * 1000

        /** 当前存活的实例（补抓需要实例方法 `activeNotifications`）。 */
        @Volatile
        private var instance: AutoBookListenerService? = null

        /**
         * 供 Dart 侧在**每次 drain 之前**调用：把通知栏里仍存在、但服务当时没接到的通知补入队。
         *
         * @return 补入队条数；服务未被系统绑定（拿不到实例）时返回 `-1`。
         */
        fun catchUpNow(): Int {
            val svc = instance ?: return -1
            return svc.catchUp("channel")
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        AutoBookDiagnostics.load(this)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** 系统把服务绑上了（此后 `onNotificationPosted` 才会来）。 */
    override fun onListenerConnected() {
        super.onListenerConnected()
        AutoBookDiagnostics.noteConnected(this, true)
        Log.i(TAG, "onListenerConnected → 立即补抓通知栏（服务未连接期间发布的通知不会补发）")
        catchUp("connect")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        AutoBookDiagnostics.noteConnected(this, false)
        Log.w(TAG, "onListenerDisconnected → 此后实时通知不再送达")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val decision = handle(sbn, fromCatchUp = false)
        // 非白名单是绝大多数（每个 App 的每条通知都算）→ 不打日志，否则日志会被淹掉
        if (decision != Decision.NOT_WATCHED) {
            Log.i(TAG, "posted pkg=${sbn.packageName} → $decision")
        }
    }

    /**
     * 拉取通知栏里**现存的**全部通知过一遍，把其中应当记账的补入队。
     *
     * 必须在服务已连接时调用（`activeNotifications` 否则会抛异常）。
     */
    fun catchUp(reason: String): Int {
        val active: Array<StatusBarNotification>? = try {
            activeNotifications
        } catch (t: Throwable) {
            Log.w(TAG, "catchUp($reason) 取 activeNotifications 失败：$t")
            return -1
        }
        if (active == null) {
            Log.w(TAG, "catchUp($reason) 服务未连接，跳过")
            return -1
        }
        val now = System.currentTimeMillis()
        var added = 0
        for (sbn in active) {
            if (now - sbn.postTime > CATCH_UP_MAX_AGE_MS) continue
            if (handle(sbn, fromCatchUp = true) == Decision.CAPTURED) added++
        }
        Log.i(TAG, "catchUp($reason) 活动通知=${active.size} 补入队=$added")
        AutoBookDiagnostics.noteCatchUp(this, active.size, added)
        // 「识别到 N 笔」只在这里弹一次（逐条弹会被同 id 反复覆盖）
        if (added > 0) {
            AutoBookNotifier.showPending(this, AutoBookQueue.pendingCount(this))
        }
        return added
    }

    /**
     * 单条通知的完整判定链：白名单 → 组摘要 → 空正文 → 去重 → 入队。
     *
     * 抽成函数是为了让**实时回调与补抓共用同一条判定链** —— 两处各写一遍必然漂移。
     */
    private fun handle(sbn: StatusBarNotification, fromCatchUp: Boolean): Decision {
        if (!AutoBookPackages.isWatched(sbn.packageName)) {
            AutoBookDiagnostics.noteSkippedNotWatched()
            return Decision.NOT_WATCHED
        }

        val extras = sbn.notification?.extras
        if (extras == null) {
            AutoBookDiagnostics.noteSkippedEmpty()
            return Decision.EMPTY
        }

        // 组摘要（系统把多条通知聚合成一条汇总时发的条目）直接丢：
        // 它的正文是 `[2条]微信支付: 已支付¥0.01`（真机 Redmi K50 实测），与子通知文案不同 →
        // Dart 侧指纹也不同 → 不过滤会把**同一笔支付记两遍**。真实内容以子通知为准
        // （Dart 侧另有 `[N条]` 前缀兜底，两边互不依赖）。
        val isGroupSummary =
            ((sbn.notification?.flags ?: 0) and Notification.FLAG_GROUP_SUMMARY) != 0 ||
                extras.getBoolean("android.isGroupSummary", false)
        if (isGroupSummary) {
            AutoBookDiagnostics.noteSkippedGroupSummary()
            return Decision.GROUP_SUMMARY
        }

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val subText = extras.getCharSequence(Notification.EXTRA_SUB_TEXT)?.toString().orEmpty()
        // 三个正文位全空的（如纯进度通知）没有解析价值
        if (title.isEmpty() && text.isEmpty() && bigText.isEmpty()) {
            AutoBookDiagnostics.noteSkippedEmpty()
            return Decision.EMPTY
        }

        val added = AutoBookQueue.enqueueNotification(
            this,
            sbn.packageName,
            title,
            text,
            bigText,
            subText,
            sbn.postTime,
            fromCatchUp,
        )
        if (!added) {
            AutoBookDiagnostics.noteSkippedDedup()
            return Decision.DEDUP
        }

        AutoBookDiagnostics.noteCapture(this, sbn.packageName)
        if (!fromCatchUp) {
            AutoBookNotifier.showPending(this, AutoBookQueue.pendingCount(this))
        }
        return Decision.CAPTURED
    }
}
