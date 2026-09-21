import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../core/platform_paths.dart';
import '../../domain/models/comic.dart';
import '../han1me_repository.dart';
import 'json_store.dart';

class ComicReaderState {
  const ComicReaderState({this.mode = 0, this.background = 'black', this.progress = const {}});
  final int mode;
  final String background;
  final Map<String, int> progress;
  Map<String, dynamic> toJson() => {'mode': mode, 'background': background, 'progress': progress};
  factory ComicReaderState.fromJson(Map<String, dynamic> json) => ComicReaderState(mode: ((json['mode'] as int? ?? 0).clamp(0, 5)), background: json['background'] as String? ?? 'black', progress: (json['progress'] as Map? ?? const {}).map((key, value) => MapEntry('$key', value as int? ?? 0)));
}

class ComicReaderStore {
  final _store = JsonStore();
  Future<ComicReaderState> load() async => ComicReaderState.fromJson(await _store.read('comic_reader.json'));
  Future<void> save(ComicReaderState state) => _store.write('comic_reader.json', state.toJson());
}

class ComicLibraryState {
  const ComicLibraryState({this.watchLater = const [], this.favorites = const []});
  final List<ComicCard> watchLater;
  final List<ComicCard> favorites;
  Map<String, dynamic> toJson() => {'watchLater': watchLater.map((item) => item.toJson()).toList(), 'favorites': favorites.map((item) => item.toJson()).toList()};
  factory ComicLibraryState.fromJson(Map<String, dynamic> json) => ComicLibraryState(watchLater: _cards(json['watchLater']), favorites: _cards(json['favorites']));
  static List<ComicCard> _cards(Object? value) => (value as List? ?? const []).whereType<Map>().map((item) => ComicCard.fromJson(Map<String, dynamic>.from(item))).toList();
}

final comicLibraryProvider = AsyncNotifierProvider<ComicLibraryController, ComicLibraryState>(ComicLibraryController.new);

class ComicLibraryController extends AsyncNotifier<ComicLibraryState> {
  final _store = JsonStore();
  @override Future<ComicLibraryState> build() async => ComicLibraryState.fromJson(await _store.read('comic_library.json'));
  Future<void> setWatchLater(ComicCard comic, bool enabled) => _set(comic, enabled, watchLater: true);
  Future<void> setFavorite(ComicCard comic, bool enabled) => _set(comic, enabled, watchLater: false);
  Future<void> _set(ComicCard comic, bool enabled, {required bool watchLater}) async {
    final current = state.value ?? const ComicLibraryState();
    final items = (watchLater ? current.watchLater : current.favorites).where((item) => item.id != comic.id).toList();
    if (enabled) items.insert(0, comic);
    final next = watchLater ? ComicLibraryState(watchLater: items, favorites: current.favorites) : ComicLibraryState(watchLater: current.watchLater, favorites: items);
    state = AsyncData(next);
    await _store.write('comic_library.json', next.toJson());
  }
}

class ComicCacheEntry {
  const ComicCacheEntry({required this.id, required this.title, required this.coverUrl, required this.archivePath, required this.pageCount, required this.category});
  final String id;
  final String title;
  final String coverUrl;
  final String archivePath;
  final int pageCount;
  final String category;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'coverUrl': coverUrl, 'archivePath': archivePath, 'pageCount': pageCount, 'category': category};
  factory ComicCacheEntry.fromJson(Map<String, dynamic> json) => ComicCacheEntry(id: json['id'] as String? ?? '', title: json['title'] as String? ?? '', coverUrl: json['coverUrl'] as String? ?? '', archivePath: json['archivePath'] as String? ?? '${json['directory'] ?? ''}.zip', pageCount: json['pageCount'] as int? ?? 0, category: json['category'] as String? ?? defaultComicCategory);
}

const defaultComicCategory = '默认';

final comicCacheProvider = AsyncNotifierProvider<ComicCacheController, List<ComicCacheEntry>>(ComicCacheController.new);

class ComicCacheController extends AsyncNotifier<List<ComicCacheEntry>> {
  final _store = JsonStore();
  static const _categoriesKey = 'comic_cache_categories.json';
  // 缓存/删除/解压串行排队：并发操作同一漫画会互相删除工作目录、损坏归档。
  Future<void> _opQueue = Future<void>.value();

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _opQueue.then((_) => operation());
    _opQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  @override Future<List<ComicCacheEntry>> build() async => ((await _store.read('comic_cache.json'))['items'] as List? ?? const []).whereType<Map>().map((item) => ComicCacheEntry.fromJson(Map<String, dynamic>.from(item))).toList();
  Future<void> cache(ComicDetail detail, {String category = defaultComicCategory}) => _enqueue(() => _cache(detail, category: category));

  Future<void> _cache(ComicDetail detail, {required String category}) async {
    final storage = await appStorageDirectory();
    final rootDirectory = Directory(path.join(storage.path, 'Comic'));
    await rootDirectory.create(recursive: true);
    final directory = Directory(path.join(rootDirectory.path, '.${detail.id}'));
    final archiveFile = File(path.join(rootDirectory.path, '${detail.id}.zip'));
    final temporaryArchive = File('${archiveFile.path}.part');
    if (await temporaryArchive.exists()) await temporaryArchive.delete();
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
    try {
      for (var index = 0; index < detail.imageUrls.length; index++) {
        final output = File(path.join(directory.path, '${index + 1}.image'));
        await _downloadImage(detail.imageUrls[index], output);
      }
    } catch (_) {
      if (await directory.exists()) await directory.delete(recursive: true);
      rethrow;
    }
    final encoder = ZipFileEncoder();
    encoder.create(temporaryArchive.path);
    await encoder.addDirectory(directory, includeDirName: false);
    await encoder.close();
    if (!await temporaryArchive.exists() || await temporaryArchive.length() == 0) throw StateError('Comic archive was not created');
    if (await archiveFile.exists()) await archiveFile.delete();
    await temporaryArchive.rename(archiveFile.path);
    await directory.delete(recursive: true);
    final entry = ComicCacheEntry(id: detail.id, title: detail.title, coverUrl: detail.coverUrl, archivePath: archiveFile.path, pageCount: detail.pageCount, category: category);
    final next = [entry, ...?state.value?.where((item) => item.id != detail.id)];
    state = AsyncData(next);
    await _store.write('comic_cache.json', {'items': next.map((item) => item.toJson()).toList()});
  }

  Future<void> _downloadImage(String url, File output) async {
    Object? lastError;
    final client = ref.read(han1meHttpClientProvider);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await client.download(url, output.path);
        if (await output.length() > 0) return;
      } catch (error) {
        lastError = error;
        if (await output.exists()) await output.delete();
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    throw StateError('Unable to download comic image: $lastError');
  }

  Future<List<String>> categories() async {
    final saved = (await _store.read(_categoriesKey))['items'] as List? ?? const [];
    return <String>{defaultComicCategory, ...saved.whereType<String>()}.toList();
  }

  Future<void> addCategory(String category) async {
    final value = category.trim();
    if (value.isEmpty || value == defaultComicCategory) return;
    final currentCategories = await categories();
    if (currentCategories.contains(value)) return;
    await _store.write(_categoriesKey, {'items': [...currentCategories.where((item) => item != defaultComicCategory), value]});
  }

  Future<void> deleteCategory(String category) async {
    if (category == defaultComicCategory) return;
    final current = state.value ?? const [];
    final next = current.map((entry) => entry.category == category ? ComicCacheEntry(id: entry.id, title: entry.title, coverUrl: entry.coverUrl, archivePath: entry.archivePath, pageCount: entry.pageCount, category: defaultComicCategory) : entry).toList();
    state = AsyncData(next);
    await _store.write('comic_cache.json', {'items': next.map((item) => item.toJson()).toList()});
    final currentCategories = await categories();
    await _store.write(_categoriesKey, {'items': currentCategories.where((item) => item != defaultComicCategory && item != category).toList()});
  }
  Future<void> delete(ComicCacheEntry entry) => _enqueue(() async {
    final archive = File(entry.archivePath);
    if (await archive.exists()) await archive.delete();
    final next = (state.value ?? const []).where((item) => item.id != entry.id).toList();
    state = AsyncData(next);
    await _store.write('comic_cache.json', {'items': next.map((item) => item.toJson()).toList()});
  });

  Future<List<String>> extract(ComicCacheEntry entry) => _enqueue(() async {
    if (entry.pageCount <= 0) return const <String>[];
    final root = await getTemporaryDirectory();
    final directory = Directory(path.join(root.path, 'comic_reader', entry.id));
    if (!await directory.exists() || (await directory.list().length) < entry.pageCount) {
      if (await directory.exists()) await directory.delete(recursive: true);
      await directory.create(recursive: true);
      // 解码走 InputFileStream：按条目惰性解压，避免整个压缩包驻留内存。
      final archive = ZipDecoder().decodeStream(InputFileStream(entry.archivePath));
      for (final file in archive.files) {
        if (!file.isFile) continue;
        await File(path.join(directory.path, file.name)).writeAsBytes(file.content as List<int>);
      }
    }
    return List.generate(entry.pageCount, (index) => path.join(directory.path, '${index + 1}.image'));
  });
}
