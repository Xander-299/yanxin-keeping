// @dart=3.6
// 本机专用 build_runner 直跑入口（绕过 bootstrap 的子进程监督链）。
//
// 背景：本机 Dart VM 起不了「需要管道 stdio」的子进程（CreateFile failed 231，
// 见 HANDOFF.md「未解决问题」）→ `dart run build_runner` 死在两处 spawn：
//   1) bootstrap 编译 AOT snapshot（`dart compile aot-snapshot` 子进程）；
//   2) 生成的 entrypoint `build.dart` 要等父进程从 stdin 发状态消息（直接跑会永远挂住）。
//
// 解法：跳过 Bootstrap / ChildProcess 协议，进程内直调 `BuildCommand.run()`，
// 并用 `TestingOverrides(checkBuilderFreshness: false)` 关掉 AOT 新鲜度检查
// （depfile 只有真编译过才存在，绕开它就不会触发 buildScriptChanged=75）。
// drift_dev 的 builder 全程进程内跑（analyzer 解析，无子进程）。
//
// 用法（在仓库根目录）：
//   dart --packages=.dart_tool/package_config.json .dart_tool/build_drift_runner.dart build
// 若 stdin 不是终端也无所谓——本脚本不读 stdin。日志走 buildLog（stdout）。
//
// ⚠️ 依赖 build_runner 2.15.1 的内部 API（pubspec.lock 已锁版本），升级时需复核。
library;

// ignore_for_file: implementation_imports, depend_on_referenced_packages, no_leading_underscores_for_library_prefixes

import 'dart:io';

import 'package:build/src/builder.dart' show Builder, BuilderOptions;
import 'package:build/src/post_process_builder.dart' show PostProcessBuilder;

import 'package:build_runner/src/bootstrap/build_process_state.dart'
    as _state;
import 'package:build_runner/src/build_plan/build_options.dart' as _plan;
import 'package:build_runner/src/build_plan/build_paths.dart' as _plan;
import 'package:build_runner/src/build_plan/builder_factories.dart'
    as _plan;
import 'package:build_runner/src/build_plan/testing_overrides.dart'
    as _plan;
import 'package:build_runner/src/build_runner_command_line.dart' as _cli;
import 'package:build_runner/src/commands/build_command.dart' as _cmd;
import 'package:drift_dev/integrations/build.dart' as _drift;
import 'package:source_gen/builder.dart' as _source_gen;

/// 与 `build_runner bootstrap` 生成的 entrypoint 完全一致的一组工厂。
final _plan.BuilderFactories _factories = _plan.BuilderFactories(
  <String, List<Builder Function(BuilderOptions)>>{
    'drift_dev:analyzer': <Builder Function(BuilderOptions)>[
      _drift.discover,
      _drift.analyzer,
    ],
    'drift_dev:drift_dev': <Builder Function(BuilderOptions)>[
      _drift.discover,
      _drift.analyzer,
      _drift.driftBuilder,
    ],
    'drift_dev:modular': <Builder Function(BuilderOptions)>[_drift.modular],
    'drift_dev:not_shared': <Builder Function(BuilderOptions)>[
      _drift.driftBuilderNotShared,
    ],
    'drift_dev:preparing_builder': <Builder Function(BuilderOptions)>[
      _drift.preparingBuilder,
    ],
    'source_gen:combining_builder': <Builder Function(BuilderOptions)>[
      _source_gen.combiningBuilder,
    ],
  },
  postProcessBuilderFactories:
      <String, PostProcessBuilder Function(BuilderOptions)>{
        'drift_dev:cleanup': _drift.driftCleanup,
        'source_gen:part_cleanup': _source_gen.partCleanup,
      },
);

Future<void> main(List<String> args) async {
  final Directory root = Directory.current;
  while (!File('${root.path}/pubspec.yaml').existsSync()) {
    if (root.parent.path == root.path) {
      stderr.writeln('找不到 pubspec.yaml，请在仓库根目录运行。');
      exit(64);
    }
    root.path; // no-op, keep analyzer happy about unused expression
    Directory.current = root.parent;
    break;
  }

  final _plan.BuildPaths buildPaths = _plan.BuildPaths.load(
    Directory.current.path,
    buildWorkspace: false,
  );
  // 与外层进程一致：拿进程锁（防并发 build 写坏 asset 缓存）。
  await _state.buildProcessState.takeLock(buildPaths);

  final _cli.BuildRunnerCommandLine? commandLine =
      await _cli.BuildRunnerCommandLine.parse(args);
  if (commandLine == null || commandLine.type != _cli.CommandType.build) {
    stderr.writeln('本入口只支持 build 命令，参数：build [目录...]');
    exit(64);
  }

  final _cmd.BuildCommand command = _cmd.BuildCommand(
    builderFactories: _factories,
    buildOptions: _plan.BuildOptions.parse(
      commandLine,
      restIsBuildDirs: true,
      currentPackage: 'yanxin',
      buildPaths: buildPaths,
    ),
    testingOverrides: const _plan.TestingOverrides(
      checkBuilderFreshness: false,
    ),
  );
  exitCode = await command.run();
}
