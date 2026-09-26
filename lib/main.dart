import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'src/app.dart';
import 'src/core/app_dio.dart';
import 'src/core/media_player_initializer.dart';
import 'src/core/playback_speed_policy.dart';
import 'src/core/settings.dart';
import 'src/core/shader_service.dart';
import 'src/data/local/json_store.dart';
import 'src/core/platform_paths.dart';
import 'src/data/local/update_installer.dart';
import 'src/features/settings/settings_controller.dart';

final _startupStopwatch = Stopwatch()..start();

/// 启动里程碑写入 exe 目录 startup_log.txt：白屏类问题凭日志直接定位卡点。
Future<void> logStartup(String message) async {
  try {
    final line = '${_startupStopwatch.elapsedMilliseconds}ms  $message';
    var file = File('${Platform.resolvedExecutable.replaceAll(RegExp(r'\\[^\\]*$'), '')}/startup_log.txt');
    try {
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      final directory = await appStorageDirectory();
      file = File('${directory.path}/startup_log.txt');
      await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
    }
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(logStartup('main enter'));
  final loadedSettings = await _loadSettings();
  unawaited(logStartup('settings loaded'));
  // 启动链路全部容错：任一初始化失败都不应让 App 起不来（上游 v1.2.0 同款）。
  if (Platform.isWindows) {
    // Windows 上预热会强制初始化 GPU 管线，部分驱动卡 20s+（白屏嫌疑）；
    // 跳过统一预热，玻璃 shader 由组件运行时按需加载。
    unawaited(logStartup('glass init skipped (windows)'));
  } else {
    try {
      await LiquidGlassWidgets.initialize().timeout(const Duration(seconds: 2));
      unawaited(logStartup('glass init done'));
    } catch (_) {
      unawaited(logStartup('glass init failed/timeout'));
    }
  }
  try {
    await PlaybackSpeedPolicy.initialize();
  } catch (_) {}
  final settings = PlaybackSpeedPolicy.isHarmonyOs && loadedSettings.playerEngine != PlayerEngine.libMpv
      ? loadedSettings.copyWith(playerEngine: PlayerEngine.libMpv)
      : loadedSettings;
  if (!identical(settings, loadedSettings)) {
    try {
      await SettingsStore(JsonStore()).save(settings);
    } catch (_) {}
  }
  try {
    MediaPlayerInitializer.bootstrap(settings);
  } catch (_) {}
  unawaited(logStartup('runApp'));
  runApp(
    LiquidGlassWidgets.wrap(
      child: ProviderScope(
        overrides: [settingsProvider.overrideWith(() => SettingsController(settings))],
        child: const Han1meApp(),
      ),
    ),
  );
  unawaited(_postLaunch());
}

Future<AppSettings> _loadSettings() async {
  try {
    return await SettingsStore(JsonStore()).load();
  } catch (_) {
    return const AppSettings();
  }
}

Future<void> _postLaunch() async {
  try {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    unawaited(logStartup('first frame rasterized'));
  } catch (_) {}
  try {
    await Future.wait([
      ShaderService.copyToStorage(),
      UpdateInstaller(createDio()).removeStaleUpdate(),
    ]);
  } catch (_) {}
}
