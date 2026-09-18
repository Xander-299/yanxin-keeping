/// 首页「本月预算」卡（真实数据）。
///
/// 数字来源：
/// - 预算金额 → [monthBudgetProvider]（按当前账本 + 首页当前月份查库）
/// - 已消费 / 日均 → 首页已加载的当月流水（[ledgerProvider] 的 `summary`），
///   所以记一笔 / 删一笔后卡片会随首页刷新自动更新，不需要额外接线。
///
/// 与旧占位卡的差别：**移除「示例」chip 与说明文案**，未设预算时给可点的引导
/// 而不是假数字（首用验收 P2 的根因就是假数据与真实 hero 自相矛盾）。
///
/// 视觉对齐页面原型 `.budget`：白卡描边 + 58 环形（墨色外描边）+ 指标两列 +
/// 虚线分割 + 圆点日均行。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/core/utils/money.dart';

import '../../application/budget_controller.dart';
import '../../application/budget_metrics.dart';
import '../../application/ledger_controller.dart';
import 'budget_edit_sheet.dart';

/// 正常（未超支）时的强调色。
const Color kBudgetOk = Tok.green;

/// 超支时的警示色。
const Color kBudgetOver = Tok.red;

/// 日均消费的圆点色（品牌琥珀）。
const Color kDotAmber = Tok.brand;

/// 剩余可消费的圆点色。
const Color kDotPurple = Tok.purple;

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
        child: _ErrorBody(onRetry: () => ref.invalidate(monthBudgetProvider)),
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
    return ToonCard(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
            ToonRing(
              progress: view.progress,
              color: accent,
              text: view.percentText,
            ),
            const SizedBox(width: 18),
            _Metric(value: centsToYuan(view.spentCents), label: '已消费'),
            const SizedBox(width: 14),
            _Metric(
              value: centsToYuan(view.remainingCents),
              label: '剩余额度',
              valueColor: accent,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 13, bottom: 11),
          child: ToonDashedLine(),
        ),
        _DayRow(
          dotColor: kDotAmber,
          label: '本月日均消费',
          value: centsToYuan(view.dailyAvgCents),
        ),
        const SizedBox(height: 9),
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
    return Column(
      children: <Widget>[
        _TitleRow(budgetYuan: '未设置', budgetColor: Tok.ink3, onEdit: onEdit),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                '设一个月度预算，随时看到花销进度',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ToonButton(
              label: '设置$month月预算',
              kind: ToonButtonKind.tonal,
              small: true,
              onPressed: onEdit,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 13, bottom: 11),
          child: ToonDashedLine(),
        ),
        _DayRow(
          dotColor: kDotAmber,
          label: '本月日均消费',
          value: centsToYuan(view.dailyAvgCents),
        ),
        // 原型无条件渲染这两行：没设预算时「剩余每日可消费」显示「—」，
        // 少一行会让卡片高度在有/无预算之间跳动。
        const SizedBox(height: 9),
        const _DayRow(dotColor: kDotPurple, label: '剩余每日可消费', value: '—'),
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
    return ToonPress(
      dx: 0,
      dy: 0,
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            const Text(
              '本月预算',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            if (overspent) ...<Widget>[
              const SizedBox(width: 7),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Tok.redTint,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Tok.ink, width: 2),
                ),
                child: const Text(
                  '已超支',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: Tok.red,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              budgetYuan,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: budgetColor ?? Tok.ink2,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.edit_outlined, size: 17, color: Tok.ink2),
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
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: valueColor ?? Tok.ink,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Tok.ink2,
            ),
          ),
        ],
      ),
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: Border.all(color: Tok.ink, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Tok.ink2,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w900,
            color: valueColor ?? Tok.ink,
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
    return const Row(
      children: <Widget>[
        Text(
          '本月预算',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        Spacer(),
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
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
        const Text(
          '本月预算',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 8),
        const Text(
          '读取失败',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Tok.ink2,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            foregroundColor: Tok.brandDeep,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            '重试',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
