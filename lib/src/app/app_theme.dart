import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/settings.dart';

ThemeData appTheme(ColorScheme? dynamicScheme, Color seedColor, {Brightness brightness = Brightness.light, bool amoled = false}) {
  var scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
  if (amoled) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Colors.black,
      surfaceContainer: Colors.black,
      surfaceContainerHigh: Colors.black,
      surfaceContainerHighest: Colors.black,
    );
  }
  // Windows 使用内置 Noto Sans SC 可变字体：系统雅黑的回退/字重合成
  // （无 Medium/SemiBold，w500+ 全是伪加粗）与逐字回退导致粗细不一、笔画细；
  // 内置可变字体字重真实、中日常用字形全覆盖、渲染跨机器一致。
  final isWindows = !kIsWeb && Platform.isWindows;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: isWindows ? 'NotoSansSC' : null,
    fontFamilyFallback: isWindows ? const ['Microsoft YaHei UI', 'Microsoft YaHei', 'Segoe UI'] : null,
    scaffoldBackgroundColor: amoled ? Colors.black : null,
    canvasColor: amoled ? Colors.black : null,
    // 有意选择 2024 滑块外观，显式关闭 year2023（该属性已弃用但未来才会默认关闭）。
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
  );
}

extension AppThemeColorSeed on AppThemeColor {
  Color seedColor(String customColor) => switch (this) {
        AppThemeColor.rose => const Color(0xffb3265a),
        AppThemeColor.blue => const Color(0xff00639b),
        AppThemeColor.teal => const Color(0xff006b5f),
        AppThemeColor.amber => const Color(0xff875400),
        AppThemeColor.green => const Color(0xff386a20),
        AppThemeColor.orange => const Color(0xff9b4400),
        AppThemeColor.indigo => const Color(0xff4a5f9e),
        AppThemeColor.pink => const Color(0xff9c3c66),
        AppThemeColor.purple => const Color(0xff6d3f90),
        // 容错解析：备份导入可能带非法值，根 build 抛异常会导致整个 App 白屏。
        AppThemeColor.custom => Color(int.tryParse('ff$customColor', radix: 16) ?? 0xff6d3f90),
      };
}
