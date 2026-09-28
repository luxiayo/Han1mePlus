import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/han1me_repository.dart';
import '../../domain/models/library.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';
import '../../data/local/library_repository.dart';

/// 收藏库同步进度：当前步骤 0-4（稍后再看/喜欢的影片/播放清单/观看历史/我的订阅），
/// -1 表示空闲。加载 UI 用它给用户分步预期提示。
final librarySyncStepProvider = StateProvider<int>((_) => -1);

/// 最近一次同步尝试时间（含失败）：收藏页用它判断缓存是否过期、触发后台
/// 静默刷新；失败也不会立刻重试，等下次过期再试。
final librarySyncedAtProvider = StateProvider<DateTime?>((_) => null);

/// 增量刷新时订阅只抓前 N 页；更早的页依赖本地缓存（cacheRemote 会并集保留）。
const _subscriptionRefreshPages = 3;

/// 常驻不自动销毁：数据保留在内存，配合 UI 的 skipLoadingOnRefresh，
/// 过期刷新时先展示旧数据、完成后无感替换，不再每次全屏 loading。
/// 账号/设置变化时经 watch 的 future 自动重建（登出抛 NotLoggedIn）。
final remoteLibraryProvider = FutureProvider<RemoteLibrary>((ref) async {
  // 本地持久化的云端快照（上次会话的 cacheRemote 写入 remoteCached 标记）
  // 决定本次是否走订阅增量：冷启动有过快照 → 只抓前几页 + 缓存先行；
  // 真正首次登录 → 全量抓取，用户看分步进度屏拿完整数据。
  final cacheReady = (await ref.read(libraryRepositoryProvider).load()).remoteCached;
  ref.read(librarySyncedAtProvider.notifier).state = DateTime.now();
  final account = await ref.watch(accountProvider.future);
  if (account?.id == null) throw StateError('Not logged in');
  final settings = await ref.watch(settingsProvider.future);
  void reportStep(int step) {
    if (ref.exists(librarySyncStepProvider)) ref.read(librarySyncStepProvider.notifier).state = step;
  }

  reportStep(0);
  try {
    final library = await ref.watch(han1meRepositoryProvider).library(settings.resolvedBaseUrl, account!.id!, onStep: reportStep, maxSubscriptionPages: cacheReady ? _subscriptionRefreshPages : null);
    await ref.read(libraryProvider.notifier).cacheRemote(library);
    reportStep(-1);
    return library;
  } catch (_) {
    reportStep(-1);
    rethrow;
  }
});
