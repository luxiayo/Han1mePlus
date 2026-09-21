import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/media_player_initializer.dart';
import '../../core/playback_speed_policy.dart';
import '../../core/settings.dart';
import '../../data/han1me_repository.dart';
import '../../data/local/json_store.dart';

final settingsStoreProvider = Provider((_) => SettingsStore(JsonStore()));

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends AsyncNotifier<AppSettings> {
  SettingsController([this._initial]);
  final AppSettings? _initial;

  @override
  Future<AppSettings> build() async {
    final settings = _initial ?? await ref.read(settingsStoreProvider).load();
    await _syncNetworkSettings(settings);
    return settings;
  }

  AppSettings get _current => state.value ?? const AppSettings();

  Future<void> saveChanges(AppSettings Function(AppSettings current) transform) async {
    final current = _current;
    final requested = transform(current);
    final next = PlaybackSpeedPolicy.isHarmonyOs && requested.playerEngine != PlayerEngine.libMpv
        ? requested.copyWith(playerEngine: PlayerEngine.libMpv)
        : requested;
    state = AsyncData(next);
    await ref.read(settingsStoreProvider).save(next);
    MediaPlayerInitializer.update(next);
    if (current.playerEngine != next.playerEngine) MediaPlayerInitializer.apply(next);
    if (_networkSettingsChanged(current, next)) await _syncNetworkSettings(next);
  }

  Future<void> replace(AppSettings settings) async {
    final next = PlaybackSpeedPolicy.isHarmonyOs && settings.playerEngine != PlayerEngine.libMpv
        ? settings.copyWith(playerEngine: PlayerEngine.libMpv)
        : settings;
    state = AsyncData(next);
    await ref.read(settingsStoreProvider).save(next);
    MediaPlayerInitializer.update(next);
    MediaPlayerInitializer.apply(next);
    await _syncNetworkSettings(next);
  }

  bool _networkSettingsChanged(AppSettings current, AppSettings next) =>
      current.useBuiltInHosts != next.useBuiltInHosts ||
      current.useDoh != next.useDoh ||
      current.dohPreset != next.dohPreset ||
      current.dohCustomUrl != next.dohCustomUrl ||
      current.dohBootstrapIps != next.dohBootstrapIps ||
      current.dohTimeoutSeconds != next.dohTimeoutSeconds;

  // 必须用 provider 单例：setNetworkSettings 只重置所属实例的共享 HttpClient，
  // 用临时实例调用会让桌面端主链路继续用旧代理/DoH 配置直到重启。
  Future<void> _syncNetworkSettings(AppSettings settings) => ref.read(han1meHttpClientProvider).setNetworkSettings(useBuiltInHosts: settings.useBuiltInHosts, useDoh: settings.useDoh, dohPreset: settings.dohPreset, dohCustomUrl: settings.dohCustomUrl, dohBootstrapIps: settings.dohBootstrapIps, dohTimeoutSeconds: settings.dohTimeoutSeconds);

  Future<void> setPreferredQuality(String quality) async {
    await saveChanges((current) => current.copyWith(preferredQuality: _qualityInt(quality)));
  }

  int _qualityInt(String quality) {
    final numeric = int.tryParse(quality.replaceAll(RegExp(r'[^0-9]'), ''));
    return numeric ?? 720;
  }
}
