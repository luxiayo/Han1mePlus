import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/han1me_repository.dart';
import '../../domain/models/library.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';
import '../../data/local/library_repository.dart';

/// 收藏库同步进度：当前步骤 0-4（稍后再看/喜欢的影片/播放清单/观看历史/我的订阅），
/// -1 表示空闲。加载 UI 用它给用户分步预期提示。
final librarySyncStepProvider = StateProvider<int>((_) => -1);

final remoteLibraryProvider = FutureProvider.autoDispose<RemoteLibrary>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(timer.cancel);
  final account = await ref.watch(accountProvider.future);
  if (account?.id == null) throw StateError('Not logged in');
  final settings = await ref.watch(settingsProvider.future);
  void reportStep(int step) {
    if (ref.exists(librarySyncStepProvider)) ref.read(librarySyncStepProvider.notifier).state = step;
  }

  reportStep(0);
  try {
    final library = await ref.watch(han1meRepositoryProvider).library(settings.resolvedBaseUrl, account!.id!, onStep: reportStep);
    await ref.read(libraryProvider.notifier).cacheRemote(library);
    reportStep(-1);
    return library;
  } catch (_) {
    reportStep(-1);
    rethrow;
  }
});
