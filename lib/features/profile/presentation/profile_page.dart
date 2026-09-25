/// 「我的」页：头像卡 + 功能条目卡 + 品牌提示卡（F7.6 P3 卡通化，对齐原型 `scrProfile`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/providers/book_providers.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/features/export/presentation/export_sheet.dart';

/// 我的。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookAsync = ref.watch(currentBookProvider);
    return Scaffold(
      // 原型 `pbody` 用 --surface（纯白），不是全局暖白画布
      backgroundColor: Tok.paper,
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
                      icon: Icons.label_outline_rounded,
                      title: '分类管理',
                      sub: '预置分类 · 支持自定义增改删',
                      onTap: () => context.push('/categories'),
                    ),
                    _Entry(
                      icon: Icons.description_outlined,
                      title: '导入账单',
                      sub: '微信 xlsx / 支付宝 CSV，重复导入不重复记账',
                      iconBg: Tok.blueTint,
                      iconFg: Tok.blue,
                      dashedTop: true,
                      onTap: () => context.push('/import'),
                    ),
                    _Entry(
                      icon: Icons.download_outlined,
                      title: '数据导出',
                      sub: '导出 csv / 备份文件',
                      iconBg: Tok.greenTint,
                      iconFg: Tok.green,
                      dashedTop: true,
                      onTap: () => showExportSheet(context, ref),
                    ),
                    const _Entry(
                      icon: Icons.tune_rounded,
                      title: '设置',
                      sub: '主题、默认账户、货币单位',
                      iconBg: Tok.purpleTint,
                      iconFg: Tok.purple,
                      dashedTop: true,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Row(
        children: <Widget>[
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Tok.brand,
              borderRadius: BorderRadius.circular(22),
              border: Tok.inkBorder(),
              boxShadow: Tok.hard(),
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Tok.ink2,
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
    this.iconBg = Tok.brandTint,
    this.iconFg = Tok.brandDeep,
    this.dashedTop = false,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;
  final Color iconBg;
  final Color iconFg;
  final bool dashedTop;

  @override
  Widget build(BuildContext context) {
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Tok.ink, width: 2),
              boxShadow: Tok.hard(d: 2),
            ),
            child: Icon(icon, size: 20, color: iconFg),
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
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Tok.ink2,
                  ),
                ),
              ],
            ),
          ),
          if (onTap == null)
            const Text(
              '建设中',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Tok.ink3,
              ),
            )
          else
            const Icon(Icons.chevron_right, size: 18, color: Tok.ink2),
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
    return const ToonCard(
      color: Tok.brandTint,
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                  color: Tok.brandInk,
                ),
              ),
              Spacer(),
              Text(
                'v0.7.12',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Tok.brandDeep,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            '已覆盖：记一笔 → 按月看账 → 导入账单 → 统计 / 预算 / 资产 → 数据导出',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Tok.brandInk,
            ),
          ),
        ],
      ),
    );
  }
}
