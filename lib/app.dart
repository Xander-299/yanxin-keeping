/// 应用根。
///
/// 路由表在 State 里构建（每个 App 实例独立一份 GoRouter，测试互不串扰）：
/// - 壳路由（底部导航 4 tab）：`/` `/calendar` `/assets` `/profile`
/// - 全屏路由：`/record`（extra = 流水 id，`?date=` = 默认日期毫秒）、`/books`、
///   `/categories`、`/import`、`/month-picker`（日历的月份选择子页）、`/stats`（统计）、
///   `/reports`（报表，extra = [ReportsArgs]）
///
/// 搜索不是路由：F7.5 起改为覆盖在首页之上的浮层（`showSearchOverlay`）。
///
/// 主题对齐页面原型（F7.6）：卡通浅色 —— 暖白画布 + 白卡 + 2.5px 墨色描边 + 硬阴影。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/core/theme/tokens.dart';
import 'package:yanxin/features/assets/presentation/assets_page.dart';
import 'package:yanxin/features/book/presentation/book_manage_page.dart';
import 'package:yanxin/features/calendar/presentation/calendar_page.dart';
import 'package:yanxin/features/calendar/presentation/month_picker_page.dart';
import 'package:yanxin/features/category/presentation/category_manage_page.dart';
import 'package:yanxin/features/import/presentation/import_page.dart';
import 'package:yanxin/features/ledger/presentation/home_page.dart';
import 'package:yanxin/features/nav/presentation/app_shell.dart';
import 'package:yanxin/features/onboarding/presentation/onboarding_page.dart';
import 'package:yanxin/features/profile/presentation/profile_page.dart';
import 'package:yanxin/features/record/presentation/record_page.dart';
import 'package:yanxin/features/reports/application/reports_controller.dart';
import 'package:yanxin/features/reports/presentation/reports_page.dart';
import 'package:yanxin/features/stats/presentation/stats_page.dart';

/// 品牌琥珀（底栏中央按钮 / 选中态）。
const Color kBrandOrange = Tok.brand;

class YanxinApp extends StatefulWidget {
  const YanxinApp({super.key});

  @override
  State<YanxinApp> createState() => _YanxinAppState();
}

class _YanxinAppState extends State<YanxinApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (BuildContext _, GoRouterState _, StatefulNavigationShell shell) =>
            AppShell(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[GoRoute(path: '/', builder: (_, _) => const HomePage())],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/calendar',
                builder: (_, _) => const CalendarPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/assets',
                builder: (_, _) => const AssetsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/record',
        builder: (_, GoRouterState state) => RecordPage(
          txId: state.extra as String?,
          // 日历页「记一笔」按选中日期带入：/record?date=<毫秒>
          occurredAtMs: int.tryParse(state.uri.queryParameters['date'] ?? ''),
        ),
      ),
      GoRoute(path: '/books', builder: (_, _) => const BookManagePage()),
      GoRoute(path: '/import', builder: (_, _) => const ImportPage()),
      GoRoute(path: '/month-picker', builder: (_, _) => const MonthPickerPage()),
      GoRoute(path: '/stats', builder: (_, _) => const StatsPage()),
      GoRoute(
        path: '/reports',
        // extra = ReportsArgs（档位 / 年月，可空：为空沿用 controller 当前状态）
        builder: (_, GoRouterState state) =>
            ReportsPage(args: state.extra as ReportsArgs?),
      ),
      GoRoute(
        path: '/categories',
        builder: (_, _) => const CategoryManagePage(),
      ),
      // 新手引导（F7.14）：首启由 AppShell 判定后 push；也可从「我的」随时重看
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingPage()),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '颜芯记账',
      theme: buildToonTheme(),
      routerConfig: _router,
    );
  }
}
