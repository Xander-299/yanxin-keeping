/// 新手引导页（F7.14）：7 页全屏导览，一页一件事。
///
/// 入口两处：
/// - **首启自动**（仅全新安装）：`AppShell` 首帧后 `push('/onboarding')`；
/// - **手动重看**：「我的 → 新手引导」。
///
/// 退出三条路径（跳过 / 开始记账 / 系统返回）都是 `pop()`，而 pop 后本页会从树上摘掉
/// → **「看过」标记统一在 `dispose()` 里落库**，不必三处各写一遍（SPEC-F7.14 §3.1）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/providers/database.dart';
import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/core/theme/toon.dart';
import 'package:yanxin/data/repositories/app_meta_repository.dart';
import 'package:yanxin/features/onboarding/onboarding_keys.dart';
import 'package:yanxin/features/onboarding/presentation/widgets/onboarding_slides.dart';

/// 新手引导全屏页。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pages = PageController();
  int _index = 0;

  /// `dispose()` 里不能再用 `ref` → 仓储在 `initState` 取出留存。
  late final AppMetaRepository _meta;

  @override
  void initState() {
    super.initState();
    _meta = ref.read(appMetaRepositoryProvider);
  }

  @override
  void dispose() {
    unawaited(_markSeen());
    _pages.dispose();
    super.dispose();
  }

  /// 落「看过」标记。写失败静默吞掉：引导是锦上添花，不能因一次 IO 抖动冒出未捕获异常，
  /// 更不能把用户困在引导页。
  Future<void> _markSeen() async {
    try {
      await _meta.set(kOnboardingDoneKey, kOnboardingDoneValue);
    } catch (_) {
      // 忽略
    }
  }

  int get _lastIndex => kOnboardingSlides.length - 1;

  void _next() {
    if (_index >= _lastIndex) return;
    unawaited(
      _pages.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      ),
    );
  }

  void _jump(int index) {
    unawaited(
      _pages.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      ),
    );
  }

  void _close() {
    // 从「我的」进来时能 pop 回我的；首启时 pop 回首页。（壳下 push().then 不兑现，这里不需要它）
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLast = _index == _lastIndex;
    return Scaffold(
      backgroundColor: Tok.canvas,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(index: _index, onJump: _jump, onSkip: _close),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: kOnboardingSlides.length,
                onPageChanged: (int i) => setState(() => _index = i),
                itemBuilder: (BuildContext _, int i) =>
                    _SlideView(slide: kOnboardingSlides[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
              child: ToonButton(
                block: true,
                label: isLast ? '开始记账' : '下一步',
                onPressed: isLast ? _close : _next,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶行：7 点进度（可点跳页）+ 右上「跳过」。
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.index,
    required this.onJump,
    required this.onSkip,
  });

  final int index;
  final ValueChanged<int> onJump;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 2),
      child: Row(
        children: <Widget>[
          // 左侧留白与右侧「跳过」等宽，进度点才真居中
          const SizedBox(width: 48),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (int i = 0; i < kOnboardingSlides.length; i++)
                    _Dot(active: i == index, onTap: () => onJump(i)),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: Align(
              alignment: Alignment.centerRight,
              child: ToonPress(
                dx: 1.5,
                dy: 1.5,
                onTap: onSkip,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(
                    '跳过',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Tok.ink2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ToonPress(
      dx: 0,
      dy: 0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: active ? 18 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? Tok.brand : Tok.line,
            borderRadius: BorderRadius.circular(999),
            border: active ? Border.all(color: Tok.ink, width: 1.8) : null,
          ),
        ),
      ),
    );
  }
}

/// 单页：示意图 → 标题 → 正文。中间区可滚（矮屏 / 横屏不溢出）。
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          slide.art,
          const SizedBox(height: 20),
          Text(
            slide.title,
            style: const TextStyle(
              fontSize: 22,
              height: 1.25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: Tok.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: emphasisSpans(slide.body)),
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.6,
              fontWeight: FontWeight.w600,
              color: Tok.ink2,
            ),
          ),
        ],
      ),
    );
  }
}
