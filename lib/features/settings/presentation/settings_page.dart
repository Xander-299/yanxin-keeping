/// 设置页（F7.17 起）：外观 = 浅色 / 深色 / 跟随系统。
///
/// 本批**只做外观**：「默认账户 / 货币单位」尚未实现，就不放占位行（假入口比没有更糟）。
/// 视觉沿用 F7.6 卡通语言：`ToonCard` 包三行单选，选中行 = 品牌浅底 + 墨色描边 + 硬阴影。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:yanxin/core/theme/theme_mode.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/settings/application/theme_controller.dart';

/// 设置。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ToonPalette p = context.toon;
    // 还没读出来时按默认「跟随系统」显示选中态（与 MaterialApp 的回落一致）
    final ToonThemeMode mode =
        ref.watch(themeModeProvider).value ?? ToonThemeMode.system;

    return Scaffold(
      // 设置页用纯卡片底色（与「我的」一致），不是全局暖白画布
      backgroundColor: p.paper,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          const ToonSectionTitle(title: '外观'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: ToonCard(
              padding: const EdgeInsets.all(6),
              clip: true,
              child: Column(
                children: <Widget>[
                  for (final ToonThemeMode m in ToonThemeMode.values)
                    _ModeRow(
                      mode: m,
                      selected: m == mode,
                      onTap: () =>
                          ref.read(themeModeProvider.notifier).select(m),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text(
              '· 默认「跟随系统」：手机切到深色，App 立刻跟着变\n'
              '· 选择会记住，下次打开还是这一项\n'
              '· 只影响本机外观，不影响账本数据',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: p.ink2,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个外观选项行：图标 + 标题 / 说明 + 右侧选中态。
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ToonThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Semantics(
      button: true,
      selected: selected,
      child: ToonPress(
        // 标题与副标题文本会互相包含（「深色」也是「一直使用深色」的子串），
        // 测试靠这个 key 定位行，不靠文本。
        key: ValueKey<String>('themeMode_${mode.name}'),
        dx: 2,
        dy: 2,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? p.brandTint : Colors.transparent,
            borderRadius: BorderRadius.circular(Tok.rMd),
            border: Border.all(
              color: selected ? p.ink : Colors.transparent,
              width: 2,
            ),
            boxShadow: selected ? p.hard(d: 2.5) : null,
          ),
          child: Row(
            children: <Widget>[
              Icon(
                mode.icon,
                size: 22,
                color: selected ? p.brandDeep : p.ink2,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      mode.label,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      mode.hint,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: p.ink2,
                      ),
                    ),
                  ],
                ),
              ),
              // 选中态不只靠颜色：实心对勾 + 空心圆，语义上也带 selected
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 22,
                color: selected ? p.brandDeep : p.ink3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
