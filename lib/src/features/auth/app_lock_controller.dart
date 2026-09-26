import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform_service.dart';
import '../settings/settings_controller.dart';

enum AppLockStatus { unlocking, locked, unlocked }

final appLockProvider = NotifierProvider<AppLockController, AppLockStatus>(AppLockController.new);

class AppLockController extends Notifier<AppLockStatus> {
  var _everUnlocked = false;
  var _authenticating = false;

  @override
  AppLockStatus build() {
    // 桌面端无认证通道（authenticate 恒 false）：立即解锁，不等待设置加载——
    // 否则启动期锁层会盖住整个 App（白屏观感）。
    if (_everUnlocked || PlatformService.isDesktop) {
      _everUnlocked = true;
      return AppLockStatus.unlocked;
    }
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return AppLockStatus.unlocking;
    if (!settings.appLockEnabled) {
      _everUnlocked = true;
      return AppLockStatus.unlocked;
    }
    return AppLockStatus.locked;
  }

  void markUnlocked() => _everUnlocked = true;

  Future<void> unlock() async {
    if (PlatformService.isDesktop) {
      _everUnlocked = true;
      state = AppLockStatus.unlocked;
      return;
    }
    if (_authenticating) return;
    _authenticating = true;
    try {
      final ok = await PlatformService.authenticate();
      if (ok) _everUnlocked = true;
      state = ok ? AppLockStatus.unlocked : AppLockStatus.locked;
    } catch (_) {
      state = AppLockStatus.locked;
    } finally {
      _authenticating = false;
    }
  }

  Future<void> retry() => unlock();
}
