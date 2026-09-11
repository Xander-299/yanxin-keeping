/// 首页「本月预算」卡（真实数据）。
///
/// 数字来源：
/// - 预算金额 → [monthBudgetProvider]（按当前账本 + 首页当前月份查库）
/// - 已消费 / 日均 → 首页已加载的当月流水（[ledgerProvider] 的 `summary`），
///   所以记一笔 / 删一笔后卡片会随首页刷新自动更新，不需要额外接线。
///
/// 与旧占位卡的差别：**移除「示例」chip 与说明文案**，未设预算时给可点的引导
/// 而不是假数字（首用验收 P2 的根因就是假数据与真实 hero 自相矛盾）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/utils/money.dart';

import '../../application/budget_controller.dart';
import '../../application/budget_metrics.dart';
import '../../application/ledger_controller.dart';
import 'budget_edit_sheet.dart';

/// 正常（未超支）时的强调色。
const Color kBudgetOk = Color(0xFF66BB6A);

/// 超支时的警示色。
const Color kBudgetOver = Color(0xFFEF5350);

/// 日均消费的圆点色（与日历页的点色系一致）。
const Color kDotAmber = Color(0xFFFFC978);

/// 剩余可消费的圆点色。
const Color kDotPurple = Color(0xFFB39DDB);

/// 卡片底色（与全局 cardTheme 一致，卡片自带圆角与内边距）。
const Color kBudgetCardBg = Color(0xFF1B1B1D);

/// 预算卡。
class BudgetCard extends ConsumerWidget {
  const BudgetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider).value;
    final budgetAsync = ref.watch(monthBudgetProvider);
    if (ledger == null) return const SizedBox.shrink();

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // 首次加载：给个中性骨架，避免先闪一下「未设置」再跳成真实预算。
    if (budgetAsync.isLoading && !budgetAsync.hasValue) {
      return const _BudgetShell(child: _LoadingBody());
    }
    if (budgetAsync.hasError && !budgetAsync.hasValue) {
      return _BudgetShell(
        child: _ErrorBody(
          onRetry: () => ref.invalidate(monthBudgetProvider),
        ),
      );
    }

    final view = buildBudgetView(
      budgetCents: budgetAsync.value,
      spentCents: ledger.summary.expenseCents,
      year: ledger.year,
      month: ledger.month,
      nowMs: nowMs,
    );
    final int month = ledger.month;

    return _BudgetShell(
      child: view.hasBudget
          ? _FilledBody(
              view: view,
              onEdit: () => showBudgetEditSheet(context, ref, view: view),
            )
          : _EmptyBody(
              view: view,
              month: month,
              onEdit: () => showBudgetEditSheet(context, ref, view: view),
            ),
    );
  }
}

/// 卡片外壳：统一外距 / 内距 / 圆角 / 底色。
class _BudgetShell extends StatelessWidget {
  const _BudgetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: kBudgetCardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// 已设预算：标题行 + 进度环 + 两个指标 + 两条按天折算。
class _FilledBody extends StatelessWidget {
  const _FilledBody({required this.view, required this.onEdit});

  final BudgetView view;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final Color accent = view.overspent ? kBudgetOver : kBudgetOk;
    return Column(
      children: <Widget>[
        _TitleRow(
          budgetYuan: centsToYuan(view.budgetCents, group: true),
          overspent: view.overspent,
          onEdit: onEdit,
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      value: view.progress,
                      strokeWidth: 5,
                      strokeCap: StrokeCap.round,
                      color: accent,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                  Text(
                    view.percentText,
                    style: TextStyle(fontSize: 12, color: accent),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            _Metric(value: centsToYuan(view.spentCents), label: '已消费'),
            const SizedBox(width: 20),
            _Metric(
              value: centsToYuan(view.remainingCents),
              label: '剩余额度',
              valueColor: accent,
            ),
          ],
        ),
        const Divider(height: 20),
        _DayRow(
          dotColor: kDotAmber,
          label: '本月日均消费',
          value: centsToYuan(view.dailyAvgCents),
        ),
        const SizedBox(height: 8),
        _DayRow(
          dotColor: kDotPurple,
          label: '剩余每日可消费',
          // 历史月没有「剩余天数」，显示「—」而不是 0（0 会被误读成「今天不能花了」）
          value: view.dailyRemainingCents == null
              ? '—'
              : centsToYuan(view.dailyRemainingCents!),
          valueColor: view.overspent ? kBudgetOver : kBudgetOk,
        ),
      ],
    );
  }
}

/// 未设预算：**不显示任何假数字**，给一句说明 + 一个可点的「设置预算」。
class _EmptyBody extends StatelessWidget {
  const _EmptyBody({
    required this.view,
    required this.month,
    required this.onEdit,
  });

  final BudgetView view;
  final int month;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final Color muted = Colors.white.withValues(alpha: 0.55);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _TitleRow(
          budgetYuan: '未设置',
          budgetColor: muted,
          onEdit: onEdit,
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '设一个月度预算，随时看到花销进度',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onEdit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text('设置$month月预算'),
            ),
          ],
        ),
        const Divider(height: 20),
        _DayRow(
          dotColor: kDotAmber,
          label: '本月日均消费',
          value: centsToYuan(view.dailyAvgCents),
        ),
      ],
    );
  }
}

/// 标题行：左「本月预算」+ 超支小标，右金额 + 编辑图标。整行可点。
class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.budgetYuan,
    required this.onEdit,
    this.overspent = false,
    this.budgetColor,
  });

  final String budgetYuan;
  final Color? budgetColor;
  final bool overspent;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            const Text('本月预算', style: TextStyle(fontSize: 14)),
            if (overspent) ...<Widget>[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: kBudgetOver.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '已超支',
                  style: TextStyle(fontSize: 10, color: kBudgetOver),
                ),
              ),
            ],
            const Spacer(),
            Text(
              budgetYuan,
              style: TextStyle(
                fontSize: 13,
                color: budgetColor ?? Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.edit_note_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label, this.valueColor});

  final String value;
  final String label;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: valueColor ?? Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.dotColor,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final Color dotColor;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Colors.white,
          ),
        ),
      ],
    );
  }
}

/// 首次加载：占位骨架（不出现任何数字，避免与真实值不一致的闪烁）。
class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Text('本月预算', style: TextStyle(fontSize: 14)),
        const Spacer(),
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

/// 读取失败：如实告知 + 重试，而不是伪装成「未设置预算」。
class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Text('本月预算', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text(
          '读取失败',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('重试', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
