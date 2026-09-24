import 'dart:io';

import 'package:flutter/services.dart';

/// macOS 原生全屏控制：调用 NSWindow.toggleFullScreen，隐藏菜单栏和 Dock，
/// 窗口填满整个屏幕。移动端/Windows/Linux 继续使用 SystemChrome 方案。
class DesktopFullScreen {
  DesktopFullScreen._();

  static const _channel = MethodChannel('com.liar.han1meplus/fullscreen');
  static bool get _supported => Platform.isMacOS;

  /// 原生全屏期间用户按下 ESC（Swift 端拦截系统行为后转发）。
  /// 由全屏播放路由设置/清除；不设置时 ESC 仍走系统默认行为。
  static VoidCallback? onEscape;

  static void _ensureHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onEscape') onEscape?.call();
      return null;
    });
  }

  static Future<void> toggle() async {
    if (!_supported) return;
    _ensureHandler();
    try {
      await _channel.invokeMethod<void>('toggleFullScreen');
    } catch (_) {}
  }

  /// 幂等退出全屏：窗口已不在原生全屏（如用户已点绿色按钮）时为空操作。
  static Future<void> exitIfActive() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('exitFullscreenIfActive');
    } catch (_) {}
  }

  /// 开关"原生全屏期间 ESC 交由 Dart 处理"。仅在视频全屏路由打开期间开启，
  /// 其余场景保持系统默认（ESC 退出全屏）。
  static Future<void> setEscapeIntercept(bool enabled) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('setEscapeIntercept', enabled);
    } catch (_) {}
  }
}
