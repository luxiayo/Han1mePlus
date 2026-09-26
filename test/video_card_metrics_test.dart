import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_plus/src/features/shared/video_card.dart';

void main() {
  group('videoCardMetaHeightFor', () {
    test('无缩放时等于间距 + 标题盒 + 两行元信息', () {
      // 8(gap) + 46(title) + 2 + 17 + 2 + 17
      expect(videoCardMetaHeightFor(titleBoxHeight: 46, textScaler: TextScaler.noScaling), 92.0);
    });

    test('跟随系统字体缩放，间距不缩放', () {
      expect(videoCardMetaHeightFor(titleBoxHeight: 46, textScaler: const TextScaler.linear(2.0)), 8 + 46.0 + 2 + 34.0 + 2 + 34.0);
    });
  });

  group('videoCardMetrics', () {
    test('卡片高度随 metaHeight 增长', () {
      final normal = videoCardMetrics(viewportWidth: 1200, cardsPerRow: 3, horizontal: true, expanded: true, metaHeight: 92);
      final scaled = videoCardMetrics(viewportWidth: 1200, cardsPerRow: 3, horizontal: true, expanded: true, metaHeight: 92 + 46);
      expect(scaled.cardWidth, normal.cardWidth);
      expect(scaled.cardHeight - normal.cardHeight, 46);
    });

    test('桌面端横向卡片宽度固定 220', () {
      final metrics = videoCardMetrics(viewportWidth: 800, cardsPerRow: 2, horizontal: true, expanded: false, metaHeight: 92);
      expect(metrics.cardWidth, 220.0);
      expect(metrics.cardHeight, 220 * 9 / 16 + 92.0);
    });

    test('窄屏（移动端）横向卡片宽度 154', () {
      final metrics = videoCardMetrics(viewportWidth: 640, cardsPerRow: 2, horizontal: true, expanded: false);
      expect(metrics.cardWidth, 154.0);
    });

    test('宽屏按 280px 推导列数并封顶 8', () {
      expect(videoCardMetrics(viewportWidth: 1440, cardsPerRow: 2, horizontal: true, expanded: true).cardsPerRow, 5);
      expect(videoCardMetrics(viewportWidth: 1920, cardsPerRow: 2, horizontal: true, expanded: true).cardsPerRow, 6);
      expect(videoCardMetrics(viewportWidth: 2560, cardsPerRow: 2, horizontal: true, expanded: true).cardsPerRow, 8);
    });

    test('列数不低于用户设置（移动端 2 列不变），窄窗也能到 4 列', () {
      expect(videoCardMetrics(viewportWidth: 390, cardsPerRow: 2, horizontal: true, expanded: true).cardsPerRow, 2);
      expect(videoCardMetrics(viewportWidth: 1194, cardsPerRow: 2, horizontal: true, expanded: true).cardsPerRow, 4);
    });
  });
}
