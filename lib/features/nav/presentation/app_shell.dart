/// 底部导航壳：4 tab + 中央橙色「记一笔」按钮。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/app.dart'
    show kBrandOrange;
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
    Icons.calendar_month_rounded,
    Icons.add,
    Icons.account_balance_wallet_rounded,
    Icons.person_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    const Color inactive = Colors.white54;
    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        decoration: const BoxDecoration(
          color: Color(0xFF121214),
          border: Border(top: BorderSide(color: Colors.white10)),
        ),
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
                        color: kBrandOrange,
                        inactive: inactive,
                        onTap: () => onTap(slot),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  /// 槽位 → 分支 index（中央 + 不是分支）。
  static int _branchIndex(int slot) => slot < 2 ? slot : slot - 1;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.inactive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final Color inactive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color c = selected ? color : inactive;
    return InkResponse(
      onTap: onTap,
      radius: 32,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 24, color: c),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, height: 1, color: c),
          ),
        ],
      ),
    );
  }
}

/// 中央橙色 + 按钮（对齐参考图：圆角方块）。
class _CenterAddButton extends StatelessWidget {
  const _CenterAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Tooltip(
        message: '记一笔',
        child: Material(
          color: kBrandOrange,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: const SizedBox(
              width: 46,
              height: 40,
              child: Icon(Icons.add, size: 26, color: Color(0xFF241503)),
            ),
          ),
        ),
      ),
    );
  }
}
