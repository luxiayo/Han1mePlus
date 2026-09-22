import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_service.dart';
import 'settings.dart';

class PlaybackSpeedPolicy {
  const PlaybackSpeedPolicy._();

  static bool get isHarmonyOs => !kIsWeb && Platform.isAndroid && _harmonyOs;

  static bool _harmonyOs = false;
  static Future<void>? _initialization;

  static Future<void> initialize() => _initialization ??= _detect();

  static Future<void> _detect() async {
    if (kIsWeb || !Platform.isAndroid) return;
    _harmonyOs = await PlatformService.isHarmonyOs();
  }

  static void setHarmonyOs(bool value) => _harmonyOs = value;

  static double longPressSpeed(AppSettings settings, {required bool isThreeDimensional}) {
    final requested = settings.longPressPlaybackSpeed;
    if (isHarmonyOs && isThreeDimensional) return requested.clamp(1, 1.5).toDouble();
    return requested;
  }

  static bool isThreeDimensional(String? genre, String title) {
    final normalized = '${genre ?? ''} $title'.toLowerCase();
    return normalized.contains('3dcg') ||
        normalized.contains('3d') ||
        normalized.contains('三维') ||
        normalized.contains('3d动画') ||
        normalized.contains('3d動畫');
  }

  /// 大幅变速一步到位时，播放内核按音频时钟重排视频帧时间轴，画面会出现一次
  /// 可见的帧衔接跳变。这里生成按 [step] 递进的中间倍速，调用方逐步应用，
  /// 每一步的重排小到不可察，整体过渡平滑。返回值不含起始与目标倍速本身。
  static List<double> rampSteps(double from, double to, {double step = .25}) {
    final difference = to - from;
    if (difference.abs() < step) return const [];
    final direction = difference > 0 ? 1.0 : -1.0;
    final steps = <double>[];
    for (var next = from + direction * step; (to - next) * direction > 0; next += direction * step) {
      steps.add(double.parse(next.toStringAsFixed(2)));
    }
    return steps;
  }
}
