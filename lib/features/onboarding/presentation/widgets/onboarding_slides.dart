/// F7.14 新手引导的**页内容**：7 页文案 + 各自示意图。
///
/// 一页一件事，顺序固定（有单测锁）。文案里的按钮名 / 图标 / 手势是**真件口径**，
/// 改 UI 入口时务必同步回看这里与 `docs/SPEC-F7.14-onboarding.md` §3.2。
library;

import 'package:flutter/material.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/features/onboarding/presentation/widgets/onboarding_art.dart';

/// 一页引导。
class OnboardingSlide {
  const OnboardingSlide({
    required this.title,
    required this.body,
    required this.art,
  });

  final String title;

  /// 正文。支持 `**粗体**` 标记（见 [parseEmphasis]）。
  final String body;

  final Widget art;
}

/// 把 `**粗体**` 标记切成片段（纯函数，可单测）。
///
/// - 未闭合的 `**` 当普通字符，不抛错；
/// - 空串 → 空列表。
List<({String text, bool strong})> parseEmphasis(String text) {
  final List<({String text, bool strong})> out = <({String text, bool strong})>[];
  String rest = text;
  while (rest.isNotEmpty) {
    final int start = rest.indexOf('**');
    if (start < 0) {
      out.add((text: rest, strong: false));
      break;
    }
    final int end = rest.indexOf('**', start + 2);
    if (end < 0) {
      // 未闭合 → 整段当普通文字（含那对 `**`）
      out.add((text: rest, strong: false));
      break;
    }
    if (start > 0) out.add((text: rest.substring(0, start), strong: false));
    out.add((text: rest.substring(start + 2, end), strong: true));
    rest = rest.substring(end + 2);
  }
  return out;
}

/// 正文 → `TextSpan` 序列（粗体 = `brandInk` + w900）。
List<TextSpan> emphasisSpans(String text) => <TextSpan>[
  for (final ({String text, bool strong}) part in parseEmphasis(text))
    TextSpan(
      text: part.text,
      style: part.strong
          ? const TextStyle(fontWeight: FontWeight.w900, color: Tok.brandInk)
          : null,
    ),
];

/// 7 页引导内容（SPEC-F7.14 §3.2）。
const List<OnboardingSlide> kOnboardingSlides = <OnboardingSlide>[
  OnboardingSlide(
    title: '认识一下颜芯记账',
    body: 'App 里有几个**没有文字的按钮**和**藏起来的手势**，30 秒看完，以后就不会找不到。'
        '随时可以点右上角「跳过」。',
    art: WelcomeArt(),
  ),
  OnboardingSlide(
    title: '中间歪着的方块 = 记一笔',
    body: '底栏正中那个**歪 4° 的琥珀方块**是全局记账入口，四个页面都在。'
        '它故意做得跟旁边图标不一样，就是让你一眼看到。',
    art: MiniTabBarArt(),
  ),
  OnboardingSlide(
    title: '右上角这三个图标',
    body: '放大镜 = **搜流水**（分类 / 备注 / 金额都能搜）；'
        '单据 = **报表**（明细 / 分类 / 账户三档）；'
        '柱状图 = **统计**（分类占比 + 近 6 月趋势）。',
    art: MiniHeaderArt(),
  ),
  OnboardingSlide(
    title: '月份可以往回翻',
    body: '琥珀卡右上的 ‹ › 换月份（**不能翻到未来**）；'
        '预算卡标题行的**铅笔**点了改本月预算，没设预算时点卡片本身也能设。',
    art: MonthBudgetArt(),
  ),
  OnboardingSlide(
    title: '三个藏起来的手势',
    body: '这三处**光看界面看不出来** —— 记住它们，能省不少事。',
    art: GesturesArt(),
  ),
  OnboardingSlide(
    title: '还有两个页面的用法',
    body: '资产页右上角的 **+** 加账户，**点账户行**就是编辑；'
        '报表页顶部 **明细 / 分类 / 账户** 换视角看同一批流水。',
    art: AssetsReportsArt(),
  ),
  OnboardingSlide(
    title: '可以开始记账了',
    body: '想再看一遍：**我的 → 新手引导**。',
    art: DoneArt(),
  ),
];
