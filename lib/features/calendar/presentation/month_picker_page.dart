/// 月份选择子页：按年展示 12 个月的缩略日历，点某天即跳到该月该日。
///
/// 视觉参考 app_template/calendar_select.jpg（布局对齐）。
/// 有账的日期用琥珀色标出；点任意日期 → 日历页切到该月并选中该日，随后返回。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/core/utils/date.dart';

import '../application/calendar_controller.dart';

/// 月份选择子页。
class MonthPickerPage extends ConsumerStatefulWidget {
  const MonthPickerPage({super.key});

  @override
  ConsumerState<MonthPickerPage> createState() => _MonthPickerPageState();
}

class _MonthPickerPageState extends ConsumerState<MonthPickerPage> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = ref.read(calendarProvider).value?.year ?? DateTime.now().year;
  }

  Future<void> _pick(int month, int day) async {
    await ref.read(calendarProvider.notifier).jumpTo(_year, month, day: day);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final CalendarState? current = ref.watch(calendarProvider).value;
    final AsyncValue<Map<int, Set<int>>> index = ref.watch(
      yearDayIndexProvider(_year),
    );
    final Map<int, Set<int>> days = index.value ?? const <int, Set<int>>{};

    return Scaffold(
      appBar: AppBar(
        title: Text('$_year年'),
        actions: <Widget>[
          // 原型这里只有一个 muted 的「报表」占位（月选择页没有统计入口）
          const _PickerIcon(
            icon: Icons.receipt_long_rounded,
            tooltip: '报表（建设中）',
            muted: true,
          ),
        ],
      ),
      body: Container(
        color: Tok.paper,
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Column(
                  children: <Widget>[
                    for (int row = 0; row < 4; row++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            for (int col = 0; col < 3; col++)
                              Expanded(
                                child: _MiniMonth(
                                  year: _year,
                                  month: row * 3 + col + 1,
                                  daysWithTx:
                                      days[row * 3 + col + 1] ?? const <int>{},
                                  selectedMonth: current?.month,
                                  onPick: _pick,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _PillButton(
                      label: '‹ 上一年',
                      onTap: () => setState(() => _year--),
                    ),
                    const SizedBox(width: 24),
                    _PillButton(
                      label: '下一年 ›',
                      onTap: () => setState(() => _year++),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Text(
                '琥珀色 = 这一天有记账；点某一天即跳到该月该日',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Tok.ink2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个月份缩略日历（3 列 × 4 行里的一格）。
class _MiniMonth extends StatelessWidget {
  const _MiniMonth({
    required this.year,
    required this.month,
    required this.daysWithTx,
    required this.selectedMonth,
    required this.onPick,
  });

  final int year;
  final int month;
  final Set<int> daysWithTx;
  final int? selectedMonth;
  final void Function(int month, int day) onPick;

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final int leading = DateTime(year, month, 1).weekday % 7;
    final int total = daysInMonth(year, month);
    final int rows = ((leading + total) / 7).ceil();
    final bool isSelectedMonth = selectedMonth == month;

    return Padding(
      key: ValueKey<String>('mini-month-$month'),
      padding: const EdgeInsets.fromLTRB(3, 6, 3, 8),
      child: Column(
        children: <Widget>[
          // 原型 `.m-name`：居中、三级灰；当前月改品牌深色并加 `::before` 小圆点
          // （圆点单独成 widget，不要并进文本 —— 测试按 `find.text('9月')` 找标题）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (isSelectedMonth) ...<Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Tok.brandDeep,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 3),
              ],
              Text(
                '$month月',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: isSelectedMonth ? Tok.brandDeep : Tok.ink2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 原型 `.m-wk`：8px 三级灰星期表头（没有它读不出格子是周几）
          Row(
            children: <Widget>[
              for (final String w in _weekHeads)
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Tok.ink3,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          for (int r = 0; r < rows; r++)
            SizedBox(
              height: 13,
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < 7; c++)
                    Expanded(
                      child: _miniCell(
                        context,
                        day: 1 - leading + r * 7 + c,
                        total: total,
                        now: now,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniCell(
    BuildContext context, {
    required int day,
    required int total,
    required DateTime now,
  }) {
    if (day < 1 || day > total) return const SizedBox.shrink();
    final bool hasTx = daysWithTx.contains(day);
    final bool isToday =
        now.year == year && now.month == month && now.day == day;

    // 原型：`.mark`（这天有记账）= 品牌底 + 深棕字；`.today` 覆盖为墨底白字
    final Color? bg = isToday
        ? Tok.ink
        : hasTx
        ? Tok.brand
        : null;
    final Color fg = isToday
        ? Tok.paper
        : hasTx
        ? Tok.brandInk
        : Tok.ink2;

    return InkWell(
      onTap: () => onPick(month, day),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: bg,
        ),
        child: Text(
          '$day',
          style: TextStyle(
            fontSize: 8,
            height: 1,
            color: fg,
            fontWeight: isToday || hasTx ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 迷你月历的星期表头（原型 `.m-wk`）。
const List<String> _weekHeads = <String>['日', '一', '二', '三', '四', '五', '六'];

/// 子页 appbar 占位图标（muted = 三级灰）。
class _PickerIcon extends StatelessWidget {
  const _PickerIcon({
    required this.icon,
    required this.tooltip,
    this.muted = false,
  });

  final IconData icon;
  final String tooltip;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      color: muted ? Tok.ink3 : Tok.ink,
      onPressed: () => showWipToast(context, '报表 · 建设中'),
      icon: Icon(icon, size: 22),
    );
  }
}

/// 底部胶囊按钮（上一年 / 下一年）。
class _PillButton extends StatelessWidget {
  const _PillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tok.paper,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }
}
