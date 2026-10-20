import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/settings/application/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 首帧前先取一次「外观模式」（F7.17）：否则上次选的是深色时，
  // 冷启动会先渲染一帧浅色再跳深色（明显闪一下）。
  // 读库失败 / 超时都不阻断启动 —— 主题控制器内部已回落「跟随系统」。
  final ProviderContainer container = ProviderContainer();
  try {
    await container.read(themeModeProvider.future);
  } catch (_) {
    // 外观是低风险偏好，读不到就用默认值
  }

  runApp(
    UncontrolledProviderScope(container: container, child: const YanxinApp()),
  );
}
