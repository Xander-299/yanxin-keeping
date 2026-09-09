import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:yanxin/features/book/presentation/book_manage_page.dart';
import 'package:yanxin/features/category/presentation/category_manage_page.dart';
import 'package:yanxin/features/ledger/presentation/home_page.dart';
import 'package:yanxin/features/record/presentation/record_page.dart';

/// 应用根。
///
/// 路由表在 State 里构建（每个 App 实例独立一份 GoRouter，测试互不串扰）：
/// - `/`            首页（流水列表）
/// - `/record`      记一笔 / 编辑流水（extra = 流水 id）
/// - `/books`       账本管理
/// - `/categories`  分类管理
class YanxinApp extends StatefulWidget {
  const YanxinApp({super.key});

  @override
  State<YanxinApp> createState() => _YanxinAppState();
}

class _YanxinAppState extends State<YanxinApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(
        path: '/record',
        builder: (_, GoRouterState state) =>
            RecordPage(txId: state.extra as String?),
      ),
      GoRoute(path: '/books', builder: (_, _) => const BookManagePage()),
      GoRoute(
        path: '/categories',
        builder: (_, _) => const CategoryManagePage(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '颜芯记账',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
