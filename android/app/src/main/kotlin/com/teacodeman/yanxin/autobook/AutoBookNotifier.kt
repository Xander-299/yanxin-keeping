package com.teacodeman.yanxin.autobook

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.teacodeman.yanxin.MainActivity
import com.teacodeman.yanxin.R

/**
 * 自动记账的通知（F7.15 §3.7「设计乙」）。
 *
 * 「设计乙」= 入账仍**静默直入**，这里发的通知是**回执**（正文「已自动记账 N 笔」），
 * 两个按钮 `撤销` / `查看`。
 *
 * 硬约束（都踩过，别改回去）：
 * - `PendingIntent` 必须带 `FLAG_IMMUTABLE`（Android 12+ 不带任一 flag 直接抛 `IllegalArgumentException`）；
 * - 按钮**只能在展开态底部**（系统模板决定，放不了「右侧」）；
 * - 按钮里的 intent 必须**直达 Activity** —— Android 12 起禁止通知 trampoline
 *   （`BroadcastReceiver` / `Service` 里再 `startActivity` 会被拦）；
 * - 渠道 `IMPORTANCE_LOW`：进通知栏但不发声、不弹 heads-up（不打断支付后的操作流）；
 * - **固定 id 覆写 + setNumber + InboxStyle** 合并成一条，绝不每笔弹一条。
 */
object AutoBookNotifier {

    private const val CHANNEL_ID = "autobook"
    private const val CHANNEL_NAME = "自动记账"
    const val NOTIFICATION_ID = 0x7A15

    /** 与 MainActivity 约定的 extra 键。 */
    const val EXTRA_ACTION = "autobook_action"
    const val EXTRA_BATCH = "autobook_batch"

    /** 「撤销」按钮的动作值（MainActivity 落命令文件 → Dart 侧执行软删）。 */
    const val ACTION_UNDO = "undo"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "支付通知自动记账的结果回执"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    /** ① 捕获态：让用户在 App 外也知道「自动记账在生效」。 */
    fun showPending(context: Context, count: Int) {
        post(
            context,
            count = count,
            title = "识别到 $count 笔支付通知",
            text = "打开颜芯记账即可自动记入",
            lines = emptyList(),
            batchId = null,
        )
    }

    /**
     * ② 回执态：入账成功后由 Dart 侧通过 channel 回调触发。
     *
     * [batchId] 会随「撤销」按钮回到 MainActivity → 落命令文件 → Dart 侧据此软删整批。
     */
    fun showReceipt(
        context: Context,
        count: Int,
        amountText: String,
        batchId: String,
        lines: List<String>,
    ) {
        post(
            context,
            count = count,
            title = "已自动记账 $count 笔",
            text = if (amountText.isEmpty()) "点「撤销」可一键撤回" else "合计 $amountText · 点「撤销」可一键撤回",
            lines = lines,
            batchId = batchId,
        )
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        try {
            manager.cancel(NOTIFICATION_ID)
        } catch (_: Exception) {
        }
    }

    private fun post(
        context: Context,
        count: Int,
        title: String,
        text: String,
        lines: List<String>,
        batchId: String?,
    ) {
        ensureChannel(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (!manager.areNotificationsEnabled()) return

        val openApp = activityPendingIntent(context, action = null, batchId = null, requestCode = 0)
        val builder = newBuilder(context)
            .setSmallIcon(R.drawable.ic_stat_autobook)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp)
            .setNumber(count)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)

        if (batchId != null) {
            // 撤销：拉起 App 并把批次 id 带回去（落库只能由 Dart 做）
            val undo = activityPendingIntent(
                context,
                action = ACTION_UNDO,
                batchId = batchId,
                requestCode = batchId.hashCode(),
            )
            builder.addAction(android.R.drawable.ic_menu_revert, "撤销", undo)
            builder.addAction(android.R.drawable.ic_menu_view, "查看", openApp)
        }

        if (lines.isNotEmpty()) {
            val style = Notification.InboxStyle().setBigContentTitle(title)
            for (line in lines.take(5)) style.addLine(line)
            builder.setStyle(style)
        }

        try {
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (_: Exception) {
            // 通知权限被拒 / 系统拦截：入账不受影响，静默降级
        }
    }

    private fun newBuilder(context: Context): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
        }

    private fun activityPendingIntent(
        context: Context,
        action: String?,
        batchId: String?,
        requestCode: Int,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            this.action = "com.teacodeman.yanxin.autobook.ACTION"
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (action != null) putExtra(EXTRA_ACTION, action)
            if (batchId != null) putExtra(EXTRA_BATCH, batchId)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
