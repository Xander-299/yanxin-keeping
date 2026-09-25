/// 新手引导的**纯函数 / 静态内容**测试（F7.14）。
///
/// 只测页内容与 `parseEmphasis`，不 pump widget —— 这部分在本机（Dart 231 故障）也能跑。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:yanxin/features/onboarding/onboarding_keys.dart';
import 'package:yanxin/features/onboarding/presentation/widgets/onboarding_slides.dart';

void main() {
  test('引导共 7 页', () {
    expect(kOnboardingSlides, hasLength(7));
  });

  test('页面顺序固定（改顺序要同步 SPEC-F7.14 §3.2 与测试）', () {
    expect(
      kOnboardingSlides.map((OnboardingSlide s) => s.title).toList(),
      <String>[
        '认识一下颜芯记账',
        '中间歪着的方块 = 记一笔',
        '右上角这三个图标',
        '月份可以往回翻',
        '三个藏起来的手势',
        '还有两个页面的用法',
        '可以开始记账了',
      ],
    );
  });

  test('每页的标题与正文都非空（防止插页漏文案）', () {
    for (final OnboardingSlide s in kOnboardingSlides) {
      expect(s.title.trim(), isNotEmpty, reason: '标题为空：${s.title}');
      expect(s.body.trim(), isNotEmpty, reason: '正文为空：${s.title}');
    }
  });

  test('末页按钮与首启标记的口径（键名 / 取值）', () {
    expect(kOnboardingDoneKey, 'onboarding_done');
    expect(kOnboardingDoneValue, isNotEmpty);
  });

  group('parseEmphasis', () {
    test('无标记 → 单片段、非粗体', () {
      expect(parseEmphasis('普通文字'), <({String text, bool strong})>[
        (text: '普通文字', strong: false),
      ]);
    });

    test('单处粗体 → 切 3 段，中间那段是粗体', () {
      expect(parseEmphasis('点**这里**改预算'), <({String text, bool strong})>[
        (text: '点', strong: false),
        (text: '这里', strong: true),
        (text: '改预算', strong: false),
      ]);
    });

    test('多处粗体 → 全部识别', () {
      final List<({String text, bool strong})> parts = parseEmphasis(
        '**A**和**B**',
      );
      expect(parts, <({String text, bool strong})>[
        (text: 'A', strong: true),
        (text: '和', strong: false),
        (text: 'B', strong: true),
      ]);
    });

    test('未闭合的 ** 当普通文字（不抛错、不吞内容）', () {
      final List<({String text, bool strong})> parts = parseEmphasis('前面**后面');
      expect(parts, hasLength(1));
      expect(parts.single.strong, isFalse);
      expect(parts.single.text, '前面**后面');
    });

    test('空串 → 空列表', () {
      expect(parseEmphasis(''), isEmpty);
    });

    test('emphasisSpans 与 parseEmphasis 段数一致，且粗体段带样式', () {
      const String text = '**粗**细';
      final List<({String text, bool strong})> parts = parseEmphasis(text);
      expect(emphasisSpans(text), hasLength(parts.length));
      expect(emphasisSpans(text).last.style?.fontWeight, isNull);
    });
  });
}
