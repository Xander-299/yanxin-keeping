/// 「我的」页：头像卡 + 功能条目卡 + 品牌提示卡（F7.6 P3 卡通化，对齐原型 `scrProfile`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/data/providers/book_providers.dart';
import 'package:yanxin/features/export/presentation/export_sheet.dart';

/// 我的。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ToonPalette p = context.toon;
    final bookAsync = ref.watch(currentBookProvider);
    return Scaffold(
      // 原型 `pbody` 用 --surface（纯白），不是全局暖白画布
      backgroundColor: p.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            _Head(bookName: bookAsync.value?.name ?? '…'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ToonCard(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                clip: true,
                child: Column(
                  children: <Widget>[
                    _Entry(
                      icon: Icons.tips_and_updates_outlined,
                      title: '新手引导',
                      sub: '没有文字的按钮、藏起来的手势，30 秒看懂',
                      onTap: () => context.push('/onboarding'),
                    ),
                    _Entry(
                      icon: Icons.label_outline_rounded,
                      title: '分类管理',
                      sub: '预置分类 · 支持自定义增改删',
                      dashedTop: true,
                      onTap: () => context.push('/categories'),
                    ),
                    _Entry(
                      icon: Icons.bolt_rounded,
                      title: '自动记账',
                      sub: '微信 / 支付宝支付通知自动入账，可一键撤销',
                      iconBg: p.greenTint,
                      iconFg: p.green,
                      dashedTop: true,
                      onTap: () => context.push('/autobook'),
                    ),
                    _Entry(
                      icon: Icons.document_scanner_outlined,
                      title: '截图记账',
                      sub: '支付 / 订单截图 → 本地识别 → 确认后入账',
                      iconBg: p.brandTint,
                      iconFg: p.brandDeep,
                      dashedTop: true,
                      onTap: () => context.push('/receipt'),
                    ),
                    _Entry(
                      icon: Icons.description_outlined,
                      title: '导入账单',
                      sub: '微信 xlsx / 支付宝 CSV，重复导入不重复记账',
                      iconBg: p.blueTint,
                      iconFg: p.blue,
                      dashedTop: true,
                      onTap: () => context.push('/import'),
                    ),
                    _Entry(
                      icon: Icons.download_outlined,
                      title: '数据导出',
                      sub: '导出 csv / 备份文件',
                      iconBg: p.greenTint,
                      iconFg: p.green,
                      dashedTop: true,
                      onTap: () => showExportSheet(context, ref),
                    ),
                    _Entry(
                      icon: Icons.tune_rounded,
                      title: '设置',
                      sub: '外观主题：浅色 / 深色 / 跟随系统',
                      iconBg: p.purpleTint,
                      iconFg: p.purple,
                      dashedTop: true,
                      onTap: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _BrandTip(),
            ),
          ],
        ),
      ),
    );
  }
}

/// 头像卡：品牌圆角方块 + 小猪吉祥物 + 用户名 / 当前账本。
class _Head extends StatelessWidget {
  const _Head({required this.bookName});

  final String bookName;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        children: <Widget>[
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: p.brand,
              borderRadius: BorderRadius.circular(22),
              border: p.inkBorder(on: p.brand),
              boxShadow: p.hard(),
            ),
            child: const Center(child: PigMascot(size: 46)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '颜芯记账用户',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '当前账本：$bookName · 离线存储',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.ink2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 条目行：图标方块 + 标题 / 副标题 + `›`（未实现的显示「建设中」灰字）。
class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.sub,
    this.onTap,
    this.iconBg,
    this.iconFg,
    this.dashedTop = false,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;

  /// 图标底 / 图标色；`null` = 品牌浅底 / 品牌深色（`p.brandTint` / `p.brandDeep`）。
  final Color? iconBg;
  final Color? iconFg;

  final bool dashedTop;

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    final Color bg = iconBg ?? p.brandTint;
    final Color fg = iconFg ?? p.brandDeep;
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.ink, width: 2),
              boxShadow: p.hard(d: 2),
            ),
            child: Icon(icon, size: 20, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: p.ink2,
                  ),
                ),
              ],
            ),
          ),
          if (onTap == null)
            Text(
              '建设中',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: p.ink3,
              ),
            )
          else
            Icon(Icons.chevron_right, size: 18, color: p.ink2),
        ],
      ),
    );

    final Widget body = onTap == null
        ? Opacity(opacity: 0.6, child: row)
        : ToonPress(onTap: onTap, child: row);

    if (!dashedTop) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[const ToonDashedLine(), body],
    );
  }
}

/// 品牌提示卡（原型 `.card` + `--brand-tint`）。
class _BrandTip extends StatelessWidget {
  const _BrandTip();

  @override
  Widget build(BuildContext context) {
    final ToonPalette p = context.toon;
    return ToonCard(
      color: p.brandTint,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '这一版覆盖到哪',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: p.brandInk,
                ),
              ),
              const Spacer(),
              Text(
                'v0.7.17',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: p.brandDeep,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '已覆盖：记一笔 → 按月看账 → 导入账单 → 自动记账 → 统计 / 预算 / 资产 → 数据导出 → 浅色 / 深色 / 跟随系统',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: p.brandInk,
            ),
          ),
        ],
      ),
    );
  }
}
