import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_plus/src/features/shared/video_card.dart';

void main() {
  group('videoCardMetaHeightFor', () {
    test('无缩放时等于间距 + 标题 + 两行元信息', () {
      // 8(gap) + 40(title) + 2 + 17 + 2 + 17
      expect(videoCardMetaHeightFor(TextScaler.noScaling), 86.0);
    });

    test('跟随系统字体缩放，间距不缩放', () {
      expect(videoCardMetaHeightFor(const TextScaler.linear(2.0)), 8 + 80.0 + 2 + 34.0 + 2 + 34.0);
    });
  });

  group('videoCardMetrics', () {
    test('横向卡片高度随 textScaler 增长', () {
      final normal = videoCardMetrics(viewportWidth: 1200, cardsPerRow: 3, horizontal: true, expanded: true);
      final scaled = videoCardMetrics(viewportWidth: 1200, cardsPerRow: 3, horizontal: true, expanded: true, textScaler: const TextScaler.linear(2.0));
      expect(scaled.cardWidth, normal.cardWidth);
      expect(scaled.cardHeight - normal.cardHeight, videoCardMetaHeightFor(const TextScaler.linear(2.0)) - videoCardMetaHeightFor(TextScaler.noScaling));
    });

    test('桌面端横向卡片宽度固定 220', () {
      final metrics = videoCardMetrics(viewportWidth: 800, cardsPerRow: 2, horizontal: true, expanded: false);
      expect(metrics.cardWidth, 220.0);
      expect(metrics.cardHeight, 220 * 9 / 16 + videoCardMetaHeightFor(TextScaler.noScaling));
    });

    test('窄屏（移动端）横向卡片宽度 154', () {
      final metrics = videoCardMetrics(viewportWidth: 640, cardsPerRow: 2, horizontal: true, expanded: false);
      expect(metrics.cardWidth, 154.0);
    });
  });
}
