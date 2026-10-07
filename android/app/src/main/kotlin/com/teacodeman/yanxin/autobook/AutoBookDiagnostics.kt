package com.teacodeman.yanxin.autobook

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * 自动记账的**活性诊断**（F7.15 走查补丁）。
 *
 * 为什么需要它：整条链路有四个断点（系统→服务 / 服务→队列 / Dart 触发 / Dart 入账），
 * 但**每一层都是静默的** —— 用户只看到「没记上」，无法区分是没抓到、没触发、还是解析失败。
 * 这里把每层的最后一跳记下来，让 `/autobook` 页能回答「到底断在哪」。
 *
 * 设计约束：
 * - **跨进程持久化**：App 冷启动时 Service 可能已被系统重启，纯内存计数会丢 →
 *   关键事件（连接 / 捕获 / drain）**落盘覆盖写**一个小 JSON（低频，每笔支付一次）；
 * - 高频计数（如 `skippedNotWatched`，任意 App 发通知都会 +1）**只在内存累加**，
 *   随下一次落盘一起写出去，避免频繁 IO；
 * - 读盘失败一律重置为零值 —— 诊断本身绝不能影响记账。
 */
object AutoBookDiagnostics {

    private const val FILE = "autobook_diag.json"

    /** 系统是否绑定着本监听服务（`onListenerConnected` / `onListenerDisconnected`）。 */
    @Volatile var listenerConnected: Boolean = false
        private set
    @Volatile var lastConnectedAtMs: Long = 0L
        private set

    /** 最后一次「命中白名单并成功入队」的时间与来源。 */
    @Volatile var lastCaptureAtMs: Long = 0L
        private set
    @Volatile var lastCapturePkg: String = ""
        private set
    @Volatile var capturedTotal: Int = 0
        private set

    /** 被各层过滤掉的条数（用于判断「抓到了但没记账」）。 */
    @Volatile var skippedNotWatched: Int = 0
        private set
    @Volatile var skippedEmpty: Int = 0
        private set
    @Volatile var skippedDedup: Int = 0
        private set

    /** 最后一次被 Dart drain 取走的时间与条数。 */
    @Volatile var lastDrainAtMs: Long = 0L
        private set
    @Volatile var lastDrainCount: Int = 0
        private set
    @Volatile var drainedTotal: Int = 0
        private set

    private fun file(context: Context): File = File(context.filesDir, FILE)

    /** 冷启动读回上次落盘的值（不覆盖内存里已有的更新值）。 */
    @Synchronized
    fun load(context: Context) {
        val f = file(context)
        if (!f.exists()) return
        try {
            val o = JSONObject(f.readText())
            if (lastConnectedAtMs == 0L) {
                lastConnectedAtMs = o.optLong("lastConnectedAtMs", 0L)
                listenerConnected = o.optBoolean("listenerConnected", false)
            }
            if (lastCaptureAtMs == 0L) {
                lastCaptureAtMs = o.optLong("lastCaptureAtMs", 0L)
                lastCapturePkg = o.optString("lastCapturePkg", "")
                capturedTotal = o.optInt("capturedTotal", 0)
            }
            if (lastDrainAtMs == 0L) {
                lastDrainAtMs = o.optLong("lastDrainAtMs", 0L)
                lastDrainCount = o.optInt("lastDrainCount", 0)
                drainedTotal = o.optInt("drainedTotal", 0)
            }
        } catch (_: Exception) {
            // 诊断文件坏了不影响任何功能
        }
    }

    fun noteConnected(context: Context, connected: Boolean) {
        listenerConnected = connected
        if (connected) lastConnectedAtMs = System.currentTimeMillis()
        persist(context)
    }

    fun noteCapture(context: Context, pkg: String) {
        lastCaptureAtMs = System.currentTimeMillis()
        lastCapturePkg = pkg
        capturedTotal++
        persist(context)
    }

    fun noteSkippedNotWatched() {
        skippedNotWatched++
    }

    fun noteSkippedEmpty() {
        skippedEmpty++
    }

    fun noteSkippedDedup() {
        skippedDedup++
    }

    fun noteDrained(context: Context, count: Int) {
        lastDrainAtMs = System.currentTimeMillis()
        lastDrainCount = count
        drainedTotal += count
        // 空 drain 不落盘：`resumed` 触发很频繁，没必要每次都写文件
        if (count > 0) persist(context)
    }

    /** 供 Dart 侧读取的快照（JSON 字符串）。 */
    @Synchronized
    fun snapshot(context: Context): String = JSONObject()
        .put("listenerConnected", listenerConnected)
        .put("lastConnectedAtMs", lastConnectedAtMs)
        .put("lastCaptureAtMs", lastCaptureAtMs)
        .put("lastCapturePkg", lastCapturePkg)
        .put("capturedTotal", capturedTotal)
        .put("skippedNotWatched", skippedNotWatched)
        .put("skippedEmpty", skippedEmpty)
        .put("skippedDedup", skippedDedup)
        .put("lastDrainAtMs", lastDrainAtMs)
        .put("lastDrainCount", lastDrainCount)
        .put("drainedTotal", drainedTotal)
        .put("nowMs", System.currentTimeMillis())
        .toString()

    @Synchronized
    private fun persist(context: Context) {
        try {
            file(context).writeText(snapshot(context))
        } catch (_: Exception) {
            // 落盘失败只影响「跨重启可见性」，不影响本次会话
        }
    }
}
