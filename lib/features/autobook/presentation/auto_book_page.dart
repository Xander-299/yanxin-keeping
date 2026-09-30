/// 「自动记账」设置页（路由 `/autobook`，F7.15 SPEC §3.2 / §3.6）。
///
/// 职责：
/// 1. 显示**权限状态**（通知使用权 / 通知权限）并提供一键跳转 —— 通知使用权不弹系统对话框，
///    用户必须自己去系统设置开，所以这一页是**成败关键**；
/// 2. 「最近一次自动记账」+ 撤销（**不依赖通知**的兜底入口，通知被系统屏蔽时仍可用）；
/// 3. 说明识别范围、忽略规则与隐私（本 App 无 `INTERNET` 权限，数据只落本地）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/providers/data_epoch.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/core/utils/money.dart';
import 'package:yanxin/features/autobook/application/auto_book_controller.dart';
import 'package:yanxin/features/autobook/application/auto_book_notice.dart';
import 'package:yanxin/features/autobook/data/auto_book_batches.dart';
import 'package:yanxin/features/autobook/data/auto_book_bridge.dart';

/// 「通知使用权」是否已开启（原生侧实时查系统设置）。
final autoBookListenerEnabledProvider = FutureProvider<bool>(
  (Ref ref) => ref.watch(autoBookBridgeProvider).listenerEnabled(),
);

/// 通知权限是否允许（Android 13+ 含 `POST_NOTIFICATIONS`）。
final autoBookNotificationsAllowedProvider = FutureProvider<bool>(
  (Ref ref) => ref.watch(autoBookBridgeProvider).notificationsAllowed(),
);

/// 最近一批自动记账（含跨启动的批次，来自 `schema_meta` KV）。
final autoBookLatestBatchProvider = FutureProvider<AutoBookBatch?>((Ref ref) {
  ref.watch(dataEpochProvider);
  return ref.watch(autoBookBatchStoreProvider).latest();
});

class AutoBookPage extends ConsumerStatefulWidget {
  const AutoBookPage({super.key});

  @override
  ConsumerState<AutoBookPage> createState() => _AutoBookPageState();
}

class _AutoBookPageState extends ConsumerState<AutoBookPage>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置返回后自动刷新状态（用户不用手动刷新）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  void _refreshStatus() {
    ref.invalidate(autoBookListenerEnabledProvider);
    ref.invalidate(autoBookNotificationsAllowedProvider);
    ref.invalidate(autoBookLatestBatchProvider);
  }

  Future<void> _openSettings() async {
    await ref.read(autoBookBridgeProvider).openListenerSettings();
  }

  Future<void> _requestNotifications() async {
    await ref.read(autoBookBridgeProvider).requestNotificationPermission();
    _refreshStatus();
  }

  /// 手动跑一次 drain（走查用：`adb shell cmd notification post` 之后点这里）。
  Future<void> _checkNow() async {
    if (_busy) return;
    setState(() => _busy = true);
    final AutoBookDrainResult r = await ref
        .read(autoBookControllerProvider)
        .drain();
    _refreshStatus();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            r.imported > 0
                ? '新入账 ${r.imported} 笔'
                : (r.undone > 0 ? '已撤销 ${r.undone} 笔' : '没有新的支付通知'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _undoLatest(AutoBookBatch batch) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final int deleted = await ref
        .read(autoBookNoticeProvider.notifier)
        .undo(batch.batchId);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(deleted > 0 ? '已撤销 $deleted 笔' : '这批已撤销或不复存在'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<bool> listener = ref.watch(autoBookListenerEnabledProvider);
    final AsyncValue<bool> notify = ref.watch(
      autoBookNotificationsAllowedProvider,
    );
    final AsyncValue<AutoBookBatch?> latest = ref.watch(
      autoBookLatestBatchProvider,
    );

    final bool listenerOn = listener.value ?? false;

    return Scaffold(
      backgroundColor: Tok.paper,
      appBar: AppBar(
        title: const Text('自动记账'),
        actions: <Widget>[
          ToonIconButton(
            icon: Icons.refresh_rounded,
            tooltip: '检查一次',
            onPressed: _busy ? null : _checkNow,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: ToonCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _StatusRow(
                    icon: Icons.notifications_active_outlined,
                    title: '通知使用权',
                    ok: listenerOn,
                    okText: '已开启',
                    badText: listener.isLoading ? '检查中…' : '未开启',
                  ),
                  const ToonDashedLine(),
                  _StatusRow(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: '通知权限',
                    ok: notify.value ?? false,
                    okText: '已允许',
                    badText: notify.isLoading ? '检查中…' : '未允许',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ToonButton(
                          small: true,
                          kind: listenerOn
                              ? ToonButtonKind.tonal
                              : ToonButtonKind.primary,
                          icon: Icons.settings_outlined,
                          label: listenerOn ? '重新设置' : '去开启',
                          onPressed: _openSettings,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ToonButton(
                          small: true,
                          kind: ToonButtonKind.ghost,
                          icon: Icons.notifications_none_rounded,
                          label: '通知权限',
                          onPressed: _requestNotifications,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    listenerOn
                        ? '已开启：微信 / 支付宝的支付通知会被识别，打开 App 时自动入账。'
                        : '未开启时不会有任何后台行为 —— 不会监听、不会记账。'
                              '开启后本 App 只读「支付通知」的文案，数据只落本机。',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      fontWeight: FontWeight.w600,
                      color: Tok.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const ToonSectionTitle(title: '最近一次自动记账'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: ToonCard(
              color: Tok.canvas2,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: _LatestBatchBlock(
                batch: latest.value,
                loading: latest.isLoading,
                onUndo: _undoLatest,
              ),
            ),
          ),
          const ToonSectionTitle(title: '识别范围'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: ToonCard(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 4),
              child: Column(
                children: <Widget>[
                  _InfoLine('支持平台', '微信、支付宝（银行 / 云闪付等后续支持）'),
                  ToonDashedLine(),
                  _InfoLine('会记账', '支付成功、付款成功、扣款、消费、收款到账'),
                  ToonDashedLine(),
                  _InfoLine(
                    '会忽略',
                    '转账、红包、退款、优惠、充值成功、验证码、账单汇总、活动、积分、提醒',
                  ),
                  ToonDashedLine(),
                  _InfoLine('零权限兜底', '在微信 / 支付宝里「分享」账单文本到本 App 也能记'),
                ],
              ),
            ),
          ),
          const ToonSectionTitle(title: '隐私'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: ToonCard(
              color: Tok.brandTint,
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Text(
                '本 App 没有申请网络权限（Android 没有 INTERNET 权限就发不出任何数据）。'
                '通知文案、账单、流水全部只存在这台手机上，不上传、不联网。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                  color: Tok.brandInk,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '识别不准？自动记账的每一笔都能在首页提示条或上面这块「撤销」，'
              '也可以在流水里逐笔改分类。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                fontWeight: FontWeight.w600,
                color: Tok.ink3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 权限 / 能力状态行。
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.ok,
    required this.okText,
    required this.badText,
  });

  final IconData icon;
  final String title;
  final bool ok;
  final String okText;
  final String badText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: Tok.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: ok ? Tok.greenTint : Tok.redTint,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Tok.ink, width: 2),
            ),
            child: Text(
              ok ? okText : badText,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: ok ? Tok.green : Tok.redInk,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「最近一次自动记账」区块：无记录时给出引导文案。
class _LatestBatchBlock extends StatelessWidget {
  const _LatestBatchBlock({
    required this.batch,
    required this.loading,
    required this.onUndo,
  });

  final AutoBookBatch? batch;
  final bool loading;
  final Future<void> Function(AutoBookBatch) onUndo;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Text(
        '读取中…',
        style: TextStyle(fontSize: 12, color: Tok.ink2),
      );
    }
    final AutoBookBatch? b = batch;
    if (b == null) {
      return const Row(
        children: <Widget>[
          Icon(Icons.inbox_outlined, size: 20, color: Tok.ink3),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '还没有自动记过账。开启通知使用权后，下一次支付就会出现在这里。',
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${b.count} 笔 · 合计 ¥${centsToYuan(b.totalCents)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _stamp(b.atMs),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                ),
              ),
            ],
          ),
        ),
        ToonButton(
          small: true,
          kind: ToonButtonKind.danger,
          label: '撤销',
          onPressed: () => onUndo(b),
        ),
      ],
    );
  }

  static String _stamp(int ms) {
    final DateTime t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// 说明行：标题 + 内容。
class _InfoLine extends StatelessWidget {
  const _InfoLine(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 74,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Tok.ink,
              ),
            ),
          ),
          Expanded(
            child: Text(
              body,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Tok.ink2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
