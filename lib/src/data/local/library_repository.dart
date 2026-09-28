import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/library.dart';
import '../../domain/models/video.dart';
import 'json_store.dart';

final libraryRepositoryProvider = Provider((_) => LibraryRepository(JsonStore()));

class LibraryState {
  const LibraryState({this.watchLater = const [], this.favorites = const [], this.playlists = const [], this.artists = const [], this.subscriptionVideos = const {}, this.history = const [], this.remoteCached = false});
  final List<FollowingVideo> watchLater;
  final List<FollowingVideo> favorites;
  final List<Playlist> playlists;
  final List<SubscribedArtist> artists;
  final Map<String, List<FollowingVideo>> subscriptionVideos;
  final List<FollowingVideo> history;
  /// 本地库是否含云端同步快照（cacheRemote 写入并持久化）：登录态冷启动
  /// 用来决定「先展示缓存、后台增量刷新」还是走首次全量同步。
  final bool remoteCached;
  Map<String, dynamic> toJson() => {'watchLater': watchLater.map((item) => item.toJson()).toList(), 'favorites': favorites.map((item) => item.toJson()).toList(), 'playlists': playlists.map((item) => item.toJson()).toList(), 'subscribedArtists': artists.map((item) => item.toJson()).toList(), 'subscriptionVideos': subscriptionVideos.map((key, value) => MapEntry(key, value.map((item) => item.toJson()).toList())), 'history': history.map((item) => item.toJson()).toList(), 'remoteCached': remoteCached};
  factory LibraryState.fromJson(Map<String, dynamic> json) {
    List<FollowingVideo> list(String key) => ((json[key] as List?) ?? const []).whereType<Map>().map((item) => FollowingVideo.fromJson(Map<String, dynamic>.from(item))).toList();
    final entries = (json['subscriptionVideos'] as Map?) ?? const {};
    return LibraryState(watchLater: list('watchLater'), favorites: list('favorites'), playlists: ((json['playlists'] as List?) ?? const []).whereType<Map>().map((item) => Playlist.fromJson(Map<String, dynamic>.from(item))).toList(), artists: ((json['subscribedArtists'] as List?) ?? const []).whereType<Map>().map((item) => SubscribedArtist.fromJson(Map<String, dynamic>.from(item))).toList(), subscriptionVideos: entries.map((key, value) => MapEntry('$key', (value as List? ?? const []).whereType<Map>().map((item) => FollowingVideo.fromJson(Map<String, dynamic>.from(item))).toList())), history: list('history'), remoteCached: json['remoteCached'] as bool? ?? false);
  }
}

class LibraryRepository {
  LibraryRepository(this._store);
  final JsonStore _store;
  Future<LibraryState> load() async => LibraryState.fromJson(await _store.read('following_store.json'));
  Future<void> save(LibraryState state) => _store.write('following_store.json', state.toJson());
}

final libraryProvider = AsyncNotifierProvider<LibraryController, LibraryState>(LibraryController.new);
class LibraryController extends AsyncNotifier<LibraryState> {
  @override Future<LibraryState> build() => ref.read(libraryRepositoryProvider).load();
  FollowingVideo _item(VideoDetail video) => FollowingVideo(videoCode: video.id, title: video.title, coverUrl: video.coverUrl, artistName: video.artist, artistAvatarUrl: video.artistAvatarUrl, genre: video.genre, duration: video.duration, views: video.views, rating: video.rating, uploadTime: video.uploadDate, addedAt: DateTime.now().millisecondsSinceEpoch);
  Future<void> _save(LibraryState value) async { state = AsyncData(value); await ref.read(libraryRepositoryProvider).save(value); }
  Future<void> setWatchLater(VideoDetail video, bool enabled) async { final current = state.value ?? const LibraryState(); final items = current.watchLater.where((item) => item.videoCode != video.id).toList(); if (enabled) items.insert(0, _item(video)); await _save(_copy(current, watchLater: items)); }
  Future<void> setFavorite(VideoDetail video, bool enabled) async { final current = state.value ?? const LibraryState(); final items = current.favorites.where((item) => item.videoCode != video.id).toList(); if (enabled) items.insert(0, _item(video)); await _save(_copy(current, favorites: items)); }
  Future<void> removeFavorites(Set<String> videoCodes) async { final current = state.value ?? const LibraryState(); final items = current.favorites.where((item) => !videoCodes.contains(item.videoCode)).toList(); if (items.length == current.favorites.length) return; await _save(_copy(current, favorites: items)); }
  Future<void> removeWatchLater(Set<String> videoCodes) async { final current = state.value ?? const LibraryState(); final items = current.watchLater.where((item) => !videoCodes.contains(item.videoCode)).toList(); if (items.length == current.watchLater.length) return; await _save(_copy(current, watchLater: items)); }
  Future<String> createPlaylist(String title, {String description = ''}) async {
    final current = state.value ?? const LibraryState();
    final playlist = Playlist(id: '${DateTime.now().microsecondsSinceEpoch}', title: title, count: 0, description: description.isEmpty ? null : description, createdAt: DateTime.now().millisecondsSinceEpoch);
    await _save(_copy(current, playlists: [playlist, ...current.playlists]));
    return playlist.id;
  }
  Future<void> createPlaylistWithVideo(VideoDetail video, String title, {String description = ''}) async {
    final current = state.value ?? const LibraryState();
    final playlist = Playlist(id: '${DateTime.now().microsecondsSinceEpoch}', title: title, count: 1, coverUrl: video.coverUrl, description: description.isEmpty ? null : description, createdAt: DateTime.now().millisecondsSinceEpoch, videos: [_item(video)]);
    await _save(_copy(current, playlists: [playlist, ...current.playlists]));
  }
  Future<void> saveToPlaylist(VideoDetail video, String playlistId) async { final current = state.value ?? const LibraryState(); final playlists = current.playlists.map((playlist) { if (playlist.id != playlistId) return playlist; final videos = [
        _item(video),
        ...playlist.videos.where((item) => item.videoCode != video.id),
      ]; return Playlist(id: playlist.id, title: playlist.title, count: videos.length, coverUrl: video.coverUrl ?? playlist.coverUrl, videos: videos, description: playlist.description, createdAt: playlist.createdAt, sort: playlist.sort); }).toList(); await _save(_copy(current, playlists: playlists)); }
  Future<void> updatePlaylist(String playlistId, {String? title, String? description}) async {
    final current = state.value ?? const LibraryState();
    final playlists = current.playlists.map((playlist) {
      if (playlist.id != playlistId) return playlist;
      final nextTitle = title?.trim();
      return playlist.copyWith(title: nextTitle == null || nextTitle.isEmpty ? null : nextTitle, description: description?.trim());
    }).toList();
    await _save(_copy(current, playlists: playlists));
  }
  Future<void> setPlaylistSort(String playlistId, PlaylistSortOrder sort) async {
    final current = state.value ?? const LibraryState();
    final playlists = current.playlists.map((playlist) => playlist.id == playlistId ? Playlist(id: playlist.id, title: playlist.title, count: playlist.count, coverUrl: playlist.coverUrl, videos: playlist.videos, description: playlist.description, createdAt: playlist.createdAt, sort: sort) : playlist).toList();
    await _save(_copy(current, playlists: playlists));
  }
  Future<void> deletePlaylist(String playlistId) async {
    final current = state.value ?? const LibraryState();
    final playlists = current.playlists.where((playlist) => playlist.id != playlistId).toList();
    if (playlists.length == current.playlists.length) return;
    await _save(_copy(current, playlists: playlists));
  }
  Future<void> removePlaylistVideos(String playlistId, Set<String> videoCodes) async {
    final current = state.value ?? const LibraryState();
    final playlists = current.playlists.map((playlist) {
      if (playlist.id != playlistId) return playlist;
      final videos = playlist.videos.where((item) => !videoCodes.contains(item.videoCode)).toList();
      return Playlist(id: playlist.id, title: playlist.title, count: videos.length, coverUrl: videos.isEmpty ? null : playlist.coverUrl, videos: videos, description: playlist.description, createdAt: playlist.createdAt, sort: playlist.sort);
    }).toList();
    await _save(_copy(current, playlists: playlists));
  }
  Future<void> setSubscription(VideoDetail video, bool enabled) async { final name = video.artist?.trim() ?? ''; if (name.isEmpty) return; final current = state.value ?? const LibraryState(); final id = _artistId(name); final artists = current.artists.where((artist) => artist.id != id).toList(); final videos = Map<String, List<FollowingVideo>>.from(current.subscriptionVideos); if (enabled) { artists.insert(0, SubscribedArtist(id: id, name: name, avatarUrl: video.artistAvatarUrl, genre: video.genre, addedAt: DateTime.now().millisecondsSinceEpoch)); videos[id] = [_item(video), ...?videos[id]?.where((item) => item.videoCode != video.id)]; } else { videos.remove(id); } await _save(_copy(current, artists: artists, subscriptionVideos: videos)); }
  Future<void> addSubscriptionVideo(VideoDetail video) async { final current = state.value ?? const LibraryState(); final name = video.artist?.trim() ?? ''; final id = _artistId(name); if (name.isEmpty || !current.artists.any((artist) => artist.id == id)) return; final videos = Map<String, List<FollowingVideo>>.from(current.subscriptionVideos); videos[id] = [_item(video), ...?videos[id]?.where((item) => item.videoCode != video.id)]; await _save(_copy(current, subscriptionVideos: videos)); }
  Future<void> cacheRemote(RemoteLibrary remote) async {
    final current = state.value ?? const LibraryState();
    final artists = remote.subscriptionArtists;
    final videos = <String, List<FollowingVideo>>{};
    for (final artist in artists) {
      // 订阅视频做并集：增量刷新只抓了前几页，缓存里更早页的视频保留在
      // 尾部不被抹掉（增量/全量统一走并集，代价仅是云端已删条目残留）。
      final key = _artistId(artist.name);
      videos[key] = mergeVideosByVideoCode(current.subscriptionVideos[key] ?? const [], remote.subscriptions.where((video) => video.artistName == artist.name).toList());
    }
    // 合并而非整表替换：登出期间加进本地库、云端快照里没有的条目不能被
    // 下一次同步抹掉。云端为权威顺序，本地独有条目按原顺序追加在后。
    // 代价：云端已删除但本地缓存仍有的条目会在登出视图里保留——登录态
    // UI 始终以远端数据为准，可接受。
    final localOnlyArtists = current.artists.where((artist) => artist.id.isNotEmpty && artists.every((remoteArtist) => remoteArtist.id != artist.id));
    for (final artist in localOnlyArtists) {
      final cached = current.subscriptionVideos[artist.id];
      if (cached != null && cached.isNotEmpty) videos[artist.id] = cached;
    }
    await _save(_copy(
      current,
      watchLater: mergeVideosByVideoCode(current.watchLater, remote.watchLater),
      favorites: mergeVideosByVideoCode(current.favorites, remote.favorites),
      playlists: mergePlaylistsById(current.playlists, remote.playlists),
      artists: [...artists, ...localOnlyArtists],
      subscriptionVideos: videos,
      history: remote.history,
      remoteCached: true,
    ));
  }
  Future<void> replaceFavorites(List<FollowingVideo> favorites) async {
    final current = state.value ?? const LibraryState();
    await _save(_copy(current, favorites: favorites));
  }
  Future<void> replace(LibraryState value) => _save(value);
  LibraryState _copy(LibraryState value, {List<FollowingVideo>? watchLater, List<FollowingVideo>? favorites, List<Playlist>? playlists, List<SubscribedArtist>? artists, Map<String, List<FollowingVideo>>? subscriptionVideos, List<FollowingVideo>? history, bool? remoteCached}) => LibraryState(watchLater: watchLater ?? value.watchLater, favorites: favorites ?? value.favorites, playlists: playlists ?? value.playlists, artists: artists ?? value.artists, subscriptionVideos: subscriptionVideos ?? value.subscriptionVideos, history: history ?? value.history, remoteCached: remoteCached ?? value.remoteCached);
  String _artistId(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
}

/// 云端为权威顺序，本地独有（videoCode 未出现在云端）条目按原顺序追加在后。
/// 空 videoCode 的坏条目直接丢弃（无法去重也无法打开）。
List<FollowingVideo> mergeVideosByVideoCode(List<FollowingVideo> local, List<FollowingVideo> remote) {
  final seen = {for (final video in remote) video.videoCode};
  return [...remote, ...local.where((video) => video.videoCode.isNotEmpty && !seen.contains(video.videoCode))];
}

/// 播放列表按 id 合并，规则同上。
List<Playlist> mergePlaylistsById(List<Playlist> local, List<Playlist> remote) {
  final seen = {for (final playlist in remote) playlist.id};
  return [...remote, ...local.where((playlist) => playlist.id.isNotEmpty && !seen.contains(playlist.id))];
}
