import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_plus/src/core/settings.dart';

void main() {
  group('AppSettings JSON roundtrip', () {
    test('所有字段往返保持不变', () {
      const settings = AppSettings(
        homeSectionOrder: ['latest', 'subscribe'],
        hiddenHomeSections: ['previews'],
        concurrentDownloads: 3,
        searchCardsPerRow: 3,
      );
      final restored = AppSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())) as Map<String, dynamic>);
      expect(restored.homeSectionOrder, settings.homeSectionOrder);
      expect(restored.hiddenHomeSections, settings.hiddenHomeSections);
      expect(restored.concurrentDownloads, settings.concurrentDownloads);
      expect(restored.searchCardsPerRow, settings.searchCardsPerRow);
      expect(restored.playerEngine, settings.playerEngine);
    });

    test('非法值被钳制到合法区间', () {
      final restored = AppSettings.fromJson({'concurrentDownloads': 99, 'playerControlsTimeoutSeconds': 0, 'minimumVideoDurationSeconds': -5});
      expect(restored.concurrentDownloads, 5);
      expect(restored.playerControlsTimeoutSeconds, 1);
      expect(restored.minimumVideoDurationSeconds, 0);
    });

    test('缺省字段落到默认值', () {
      final restored = AppSettings.fromJson({});
      expect(restored.useLiquidGlassBottomBar, isTrue);
      expect(restored.useHomeCategoryTabs, isFalse);
      expect(restored.showHomeFeatured, isTrue);
      expect(restored.homeSectionOrder, isEmpty);
      expect(restored.hiddenHomeSections, isEmpty);
    });
  });
}
