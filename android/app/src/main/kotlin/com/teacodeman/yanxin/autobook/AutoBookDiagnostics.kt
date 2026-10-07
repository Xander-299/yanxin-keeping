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
 *   关键事件（连接 / 捕获 / drain）**落盘覆盖写**一个小 JSON；
 * - **累计值用「盘上基线 + 本进程增量」合成**（见 [recomputeTotals]）——
 *   不能靠「内存为 0 才回填」的守卫：`noteDrained` 对**空 drain** 也会刷新
 *   `lastDrainAtMs`（但刻意不落盘），会把与它同守卫的 `drainedTotal` 一起"毒化"，
 *   导致下一次任何 persist 都把真实累计值写回 0
 *   （2026-10-08 Redmi K50 实测：`drainedTotal` 8 → 0）；
 * - 读盘失败一律退回零值 —— 诊断本身绝不能影响记账。
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

    /** 组摘要被丢弃的条数（正常应当 > 0：聚合通知必然伴随摘要条目）。 */
    @Volatile var skippedGroupSummary: Int = 0
        private set

    /** 最后一次被 Dart drain 取走的时间与条数。 */
    @Volatile var lastDrainAtMs: Long = 0L
        private set
    @Volatile var lastDrainCount: Int = 0
        private set
    @Volatile var drainedTotal: Int = 0
        private set

    /** 本进程启动时盘上的值（每进程只读一次），只作为累计值的**基线**。 */
    @Volatile private var base: JSONObject = JSONObject()

    // 本进程产生的增量 —— 写盘时与 [base] 相加，绝不能直接把内存值覆盖上去。
    private var addCaptured = 0
    private var addDrained = 0
    private var addSkippedNotWatched = 0
    private var addSkippedEmpty = 0
    private var addSkippedDedup = 0
    private var addSkippedGroupSummary = 0

    /** 本进程是否已读过盘。 */
    private var loaded = false

    private fun file(context: Context): File = File(context.filesDir, FILE)

    /**
     * 冷启动读回上次落盘的值。**每进程只读一次**（重复调用无副作用）。
     *
     * 两类字段处理方式不同：
     * - **累计值**（`*Total`）由 [recomputeTotals] 合成，不在这里直接赋值；
     * - **「最后一次事件」时间戳**：仅在内存仍为初始值时回填，以免覆盖本进程的新值。
     *
     * `listenerConnected` **故意不回填** —— 它的语义是「本进程内系统是否绑定了服务」。
     * 若把上次的 `true` 恢复出来，force-stop 后重开（系统并未重新绑定）就会谎报「已绑定」，
     * 把用户和开发者一起带偏；而页面正是靠 `!listenerConnected && lastConnectedAtMs > 0`
     * 提示「设置里开着但系统没绑定（国产 ROM 后台限制）」的。
     */
    @Synchronized
    fun load(context: Context) {
        if (loaded) return
        loaded = true
        val f = file(context)
        base = if (f.exists()) {
            try {
                JSONObject(f.readText())
            } catch (_: Exception) {
                JSONObject()
            }
        } else {
            JSONObject()
        }
        if (lastConnectedAtMs == 0L) {
            lastConnectedAtMs = base.optLong("lastConnectedAtMs", 0L)
        }
        if (lastCaptureAtMs == 0L) {
            lastCaptureAtMs = base.optLong("lastCaptureAtMs", 0L)
            lastCapturePkg = base.optString("lastCapturePkg", "")
        }
        if (lastDrainAtMs == 0L) {
            lastDrainAtMs = base.optLong("lastDrainAtMs", 0L)
            lastDrainCount = base.optInt("lastDrainCount", 0)
        }
        recomputeTotals()
    }

    /**
     * 累计值 = 盘上基线 + 本进程增量。幂等，可重复调用。
     *
     * 这样即便本进程一次事件都没有（内存全 0），也不会把盘上的历史累计抹掉。
     */
    private fun recomputeTotals() {
        val b = base
        capturedTotal = b.optInt("capturedTotal", 0) + addCaptured
        drainedTotal = b.optInt("drainedTotal", 0) + addDrained
        skippedNotWatched = b.optInt("skippedNotWatched", 0) + addSkippedNotWatched
        skippedEmpty = b.optInt("skippedEmpty", 0) + addSkippedEmpty
        skippedDedup = b.optInt("skippedDedup", 0) + addSkippedDedup
        skippedGroupSummary = b.optInt("skippedGroupSummary", 0) + addSkippedGroupSummary
    }

    fun noteConnected(context: Context, connected: Boolean) {
        load(context)
        listenerConnected = connected
        if (connected) lastConnectedAtMs = System.currentTimeMillis()
        persist(context)
    }

    fun noteCapture(context: Context, pkg: String) {
        load(context)
        lastCaptureAtMs = System.currentTimeMillis()
        lastCapturePkg = pkg
        addCaptured++
        recomputeTotals()
        persist(context)
    }

    fun noteSkippedNotWatched() {
        addSkippedNotWatched++
        recomputeTotals()
    }

    fun noteSkippedEmpty() {
        addSkippedEmpty++
        recomputeTotals()
    }

    fun noteSkippedDedup() {
        addSkippedDedup++
        recomputeTotals()
    }

    fun noteSkippedGroupSummary() {
        addSkippedGroupSummary++
        recomputeTotals()
    }

    fun noteDrained(context: Context, count: Int) {
        load(context)
        lastDrainAtMs = System.currentTimeMillis()
        lastDrainCount = count
        addDrained += count
        recomputeTotals()
        // 空 drain 不落盘：`resumed` 触发很频繁，没必要每次都写文件
        if (count > 0) persist(context)
    }

    /** 供 Dart 侧读取的快照（JSON 字符串）。 */
    @Synchronized
    fun snapshot(context: Context): String {
        load(context)
        recomputeTotals()
        return JSONObject()
            .put("listenerConnected", listenerConnected)
            .put("lastConnectedAtMs", lastConnectedAtMs)
            .put("lastCaptureAtMs", lastCaptureAtMs)
            .put("lastCapturePkg", lastCapturePkg)
            .put("capturedTotal", capturedTotal)
            .put("skippedNotWatched", skippedNotWatched)
            .put("skippedEmpty", skippedEmpty)
            .put("skippedDedup", skippedDedup)
            .put("skippedGroupSummary", skippedGroupSummary)
            .put("lastDrainAtMs", lastDrainAtMs)
            .put("lastDrainCount", lastDrainCount)
            .put("drainedTotal", drainedTotal)
            .put("nowMs", System.currentTimeMillis())
            .toString()
    }

    @Synchronized
    private fun persist(context: Context) {
        try {
            // 写盘前先把基线读回来（每进程只读一次），累计值由 recomputeTotals 合成。
            load(context)
            file(context).writeText(snapshot(context))
        } catch (_: Exception) {
            // 落盘失败只影响「跨重启可见性」，不影响本次会话
        }
    }
}
