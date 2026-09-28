import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_plus/src/data/local/library_repository.dart';
import 'package:han1me_plus/src/domain/models/library.dart';

FollowingVideo video(String code) => FollowingVideo(videoCode: code, title: 't-$code', addedAt: 0);
Playlist playlist(String id) => Playlist(id: id, title: 'p-$id', count: 0);

void main() {
  group('收藏缓存合并（云端为权威顺序，本地独有条目保留）', () {
    test('本地独有收藏保留在云端列表之后，重复 videoCode 不重复', () {
      final merged = mergeVideosByVideoCode([video('local1'), video('r1'), video('local2')], [video('r2'), video('r1')]);
      expect(merged.map((v) => v.videoCode), ['r2', 'r1', 'local1', 'local2']);
    });

    test('空 videoCode 的本地坏条目被丢弃', () {
      final merged = mergeVideosByVideoCode([video(''), video('local')], const []);
      expect(merged.map((v) => v.videoCode), ['local']);
    });

    test('本地为空时原样返回云端', () {
      final merged = mergeVideosByVideoCode(const [], [video('r1'), video('r2')]);
      expect(merged.map((v) => v.videoCode), ['r1', 'r2']);
    });

    test('播放列表按 id 合并', () {
      final merged = mergePlaylistsById([playlist('localP'), playlist('r1')], [playlist('r1'), playlist('r2')]);
      expect(merged.map((p) => p.id), ['r1', 'r2', 'localP']);
    });
  });
}
