import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/han1me_repository.dart';
import '../../data/local/home_cache.dart';
import '../../domain/models/video.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';

final homeCacheProvider = Provider((_) => HomeCache());
final homeSectionsProvider = AsyncNotifierProvider<HomeSectionsController, HomeFeed>(HomeSectionsController.new);

class HomeSectionsController extends AsyncNotifier<HomeFeed> {
  @override
  Future<HomeFeed> build() async {
    ref.listen(accountProvider, (previous, next) {
      if (previous?.valueOrNull?.id != next.valueOrNull?.id) ref.invalidateSelf();
    });
    final account = await ref.watch(accountProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final cached = await ref.read(homeCacheProvider).read(settings.homeBaseUrl, account?.id);
    if (cached != null) {
      unawaited(_refreshQuietly());
      return cached;
    }
    return refresh();
  }

  // 缓存命中后的后台刷新失败不影响已展示的缓存数据，只需吞掉避免未捕获异常。
  Future<void> _refreshQuietly() async {
    try {
      await refresh();
    } catch (_) {}
  }

  Future<HomeFeed> refresh() async {
    final account = await ref.read(accountProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final feed = await ref.read(han1meRepositoryProvider).home(settings.homeBaseUrl);
    await ref.read(homeCacheProvider).write(settings.homeBaseUrl, account?.id, feed);
    state = AsyncData(feed);
    return feed;
  }
}
