package com.teacodeman.yanxin.autobook

import android.content.Context
import org.json.JSONArray
import java.io.File

/**
 * 「已经入过队」的通知指纹集合（**跨进程持久化**）。
 *
 * 为什么需要它（2026-10-08 Redmi K50 事故）：
 * 通知在**服务未连接**期间发布时，系统**不会**在服务连上后补发回调 → 那条通知
 * 永久丢失（实测：支付宝付款通知 22:29:37 发布，服务 22:31:28 才连上 → 一笔没记）。
 * 补救手段是 [AutoBookListenerService.catchUp] —— 主动拉 `getActiveNotifications()`。
 *
 * 但补抓会反复看到**同一条**仍在通知栏的通知，而队列是「取走即清空」的 →
 * 没有这层记忆，每次回前台都会重复入队，Dart 侧记为「重复 N 条」，
 * 把「上次检查：新入账 N 笔」的成功结果盖掉（与 F7.15 修掉的 last_run 覆盖同源）。
 *
 * 指纹 = `pkg|title|text|postTimeMs`。**带 postTime 才能区分「同一文案的两笔支付」**
 * （「已支付¥1.00」会有很多笔，只按文案去重会漏记）。
 */
object AutoBookSeen {

    private const val FILE = "autobook_seen.json"

    /** 只保留最近 200 条：支付通知量级下足够，且能防文件无限膨胀。 */
    private const val CAP = 200

    private val keys = ArrayDeque<String>()

    @Volatile
    private var loaded = false

    private fun file(context: Context): File = File(context.filesDir, FILE)

    @Synchronized
    fun load(context: Context) {
        if (loaded) return
        loaded = true
        val f = file(context)
        if (!f.exists()) return
        try {
            val arr = JSONArray(f.readText())
            for (i in 0 until arr.length()) {
                val s = arr.optString(i, "")
                if (s.isNotEmpty()) keys.addLast(s)
            }
        } catch (_: Exception) {
            // 读坏就当空集：最坏结果只是补抓时多入一次队（Dart 侧指纹唯一索引仍能挡住重复入账）
            keys.clear()
        }
    }

    /** 该指纹是否已经入过队。 */
    @Synchronized
    fun contains(context: Context, key: String): Boolean {
        load(context)
        return keys.contains(key)
    }

    /** 记住一条指纹；返回 false 表示**之前已经记过**（调用方据此丢弃）。 */
    @Synchronized
    fun remember(context: Context, key: String): Boolean {
        load(context)
        if (keys.contains(key)) return false
        keys.addLast(key)
        while (keys.size > CAP) keys.removeFirst()
        persist(context)
        return true
    }

    @Synchronized
    private fun persist(context: Context) {
        try {
            val arr = JSONArray()
            for (k in keys) arr.put(k)
            file(context).writeText(arr.toString())
        } catch (_: Exception) {
            // 落盘失败只影响「补抓会不会重复入队」，不会丢账
        }
    }
}
