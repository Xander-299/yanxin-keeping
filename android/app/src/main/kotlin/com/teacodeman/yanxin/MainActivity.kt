package com.teacodeman.yanxin

import android.content.Intent
import com.teacodeman.yanxin.autobook.AutoBookChannel
import com.teacodeman.yanxin.autobook.AutoBookNotifier
import com.teacodeman.yanxin.autobook.AutoBookQueue
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * 应用唯一 Activity。
 *
 * F7.15 起兼任两件事（此前是 13 行脚手架空实现）：
 * 1. 注册自动记账的平台通道 `yanxin/autobook`；
 * 2. 处理两类外部 intent：
 *    - `ACTION_SEND` + `text/plain`（从微信/支付宝「分享」一条账单文本 → 入队）
 *    - 回执通知按钮带来的 extra（`撤销` → 落命令文件，等 Dart 侧执行软删）
 *
 * ⚠️ 只**落盘**、不碰数据库（drift 是唯一 DB writer，见 SPEC-F7.15 §3.1）。
 */
class MainActivity : FlutterActivity() {

    private var autoBookChannel: AutoBookChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = AutoBookChannel(this)
        channel.attach(flutterEngine.dartExecutor.binaryMessenger)
        autoBookChannel = channel
        // 冷启动带进来的 intent（分享 / 通知按钮）在这里处理 —— 通道已就绪
        handleAutoBookIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAutoBookIntent(intent)
    }

    override fun onDestroy() {
        autoBookChannel?.detach()
        autoBookChannel = null
        super.onDestroy()
    }

    private fun handleAutoBookIntent(intent: Intent?) {
        if (intent == null) return

        if (Intent.ACTION_SEND == intent.action && intent.type?.startsWith("text/") == true) {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrBlank()) {
                AutoBookQueue.enqueueShare(this, text, System.currentTimeMillis())
            }
        }

        // 通知按钮：落命令文件，由 Dart 在下次 drain 时取走（冷启动也能撤销）
        val action = intent.getStringExtra(AutoBookNotifier.EXTRA_ACTION)
        if (action != null) {
            AutoBookQueue.writeCommand(
                this,
                action,
                intent.getStringExtra(AutoBookNotifier.EXTRA_BATCH),
            )
            intent.removeExtra(AutoBookNotifier.EXTRA_ACTION)
            intent.removeExtra(AutoBookNotifier.EXTRA_BATCH)
        }
    }
}
