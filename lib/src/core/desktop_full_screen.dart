import 'dart:io';

import 'package:flutter/services.dart';

/// macOS 原生全屏控制：调用 NSWindow.toggleFullScreen，隐藏菜单栏和 Dock，
/// 窗口填满整个屏幕。移动端/Windows/Linux 继续使用 SystemChrome 方案。
class DesktopFullScreen {
  DesktopFullScreen._();

  static const _channel = MethodChannel('com.liar.han1meplus/fullscreen');
  static bool get _supported => Platform.isMacOS;

  static Future<void> toggle() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('toggleFullScreen');
    } catch (_) {}
  }
}
