/// 底部导航壳：4 tab + 中央「记一笔」按钮（卡通风，对齐页面原型 `.tabbar`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/ledger/presentation/widgets/book_drawer.dart';

/// 导航壳：持有抽屉（账本列表）+ 底栏。
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      drawer: const BookDrawer(),
      body: navigationShell,
      bottomNavigationBar: _BottomNav(
        currentIndex: navigationShell.currentIndex,
        onTap: (int slot) {
          switch (slot) {
            case 0:
              navigationShell.goBranch(0, initialLocation: true);
            case 1:
              navigationShell.goBranch(1, initialLocation: true);
            case 2: // 中央 +：记一笔（保存后的首页刷新由记一笔页自己触发）
              context.push('/record');
            case 3:
              navigationShell.goBranch(2, initialLocation: true);
            case 4:
              navigationShell.goBranch(3, initialLocation: true);
          }
        },
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<String> _labels = <String>['首页', '日历', '', '资产', '我的'];
  static const List<IconData> _icons = <IconData>[
    Icons.home_rounded,
    Icons.calendar_today_rounded,
    Icons.add,
    Icons.account_balance_wallet_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Tok.paper,
        border: Border(top: BorderSide(color: Tok.ink, width: Tok.bw)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: <Widget>[
              for (int slot = 0; slot < 5; slot++)
                Expanded(
                  child: slot == 2
                      ? _CenterAddButton(onTap: () => onTap(2))
                      : _NavItem(
                          icon: _icons[slot],
                          label: _labels[slot],
                          selected: _branchIndex(slot) == currentIndex,
                          onTap: () => onTap(slot),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 槽位 → 分支 index（中央 + 不是分支）。
  static int _branchIndex(int slot) => slot < 2 ? slot : slot - 1;
}

/// 单个 tab：选中时图标变成一颗「品牌色 + 描边 + 硬阴影」的圆角方块。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? Tok.brandInk : Tok.ink3;
    return ToonPress(
      dx: 0,
      dy: 0,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(3),
            decoration: selected
                ? BoxDecoration(
                    color: Tok.brand,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Tok.ink, width: 2),
                    boxShadow: Tok.hard(d: 2),
                  )
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: Colors.transparent, width: 2),
                  ),
            child: Icon(icon, size: 22, color: fg),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11, height: 1, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

/// 中央「记一笔」：品牌色圆角方块 + 描边 + 硬阴影，默认歪 4°（原型 `.tab.mid .fab`）。
class _CenterAddButton extends StatelessWidget {
  const _CenterAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: '记一笔',
        child: ToonPress(
          onTap: onTap,
          child: Transform.rotate(
            angle: -4 * 3.1415926535 / 180,
            child: Container(
              width: 54,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Tok.brand,
                borderRadius: BorderRadius.circular(17),
                border: Tok.inkBorder(),
                boxShadow: Tok.hard(d: 4),
              ),
              child: const Icon(Icons.add, size: 27, color: Tok.brandInk),
            ),
          ),
        ),
      ),
    );
  }
}
