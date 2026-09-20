import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_plus/src/data/local/download_repository.dart';
import 'package:han1me_plus/src/domain/models/download.dart';

DownloadTask _task(String id, {Set<String> groupIds = const {}, String? sourceUrl}) => DownloadTask(
      id: id,
      videoCode: id,
      title: '视频 $id',
      groupIds: groupIds,
      quality: '1080',
      sourceUrl: sourceUrl,
      status: DownloadStatus.queued,
      progress: 0,
      downloadedBytes: 0,
      totalBytes: 0,
      createdAt: 1,
      updatedAt: 1,
    );

void main() {
  group('DownloadState.fromJson', () {
    test('缺少 default 分组时自动补齐', () {
      final state = DownloadState.fromJson({'groups': [], 'tasks': []});
      expect(state.groups.any((group) => group.id == 'default'), isTrue);
    });

    test('任务中指向已删分组的引用被过滤', () {
      final state = DownloadState.fromJson({
        'groups': [
          {'id': 'g1', 'name': '分组一', 'createdAt': 1},
        ],
        'tasks': [
          _task('a', groupIds: {'g1'}).toJson(),
          _task('b', groupIds: {'g1', 'ghost'}).toJson(),
        ],
      });
      expect(state.tasks.first.groupIds, {'g1'});
      expect(state.tasks.last.groupIds, {'g1'});
    });

    test('roundtrip 保留任务字段', () {
      final original = DownloadState(
        groups: const [],
        tasks: [_task('v1', sourceUrl: 'https://example.com/v.mp4')],
      );
      final restored = DownloadState.fromJson(original.toJson());
      expect(restored.tasks.single.videoCode, 'v1');
      expect(restored.tasks.single.sourceUrl, 'https://example.com/v.mp4');
      expect(restored.tasks.single.status, DownloadStatus.queued);
    });
  });
}
