import 'dart:async';

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
import 'src/data/local/update_installer.dart';
import 'src/features/settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loadedSettings = await _loadSettings();
  // 启动链路全部容错：任一初始化失败都不应让 App 起不来（上游 v1.2.0 同款）。
  try {
    await LiquidGlassWidgets.initialize();
  } catch (_) {}
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
    await Future.wait([
      ShaderService.copyToStorage(),
      UpdateInstaller(createDio()).removeStaleUpdate(),
    ]);
  } catch (_) {}
}
