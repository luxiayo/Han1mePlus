import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_plus/src/core/playback_speed_policy.dart';

void main() {
  group('PlaybackSpeedPolicy.rampSteps 倍速分步过渡', () {
    test('加速 1x→2x 不含起止值', () {
      expect(PlaybackSpeedPolicy.rampSteps(1, 2), [1.25, 1.5, 1.75]);
    });

    test('减速 2x→1x 对称', () {
      expect(PlaybackSpeedPolicy.rampSteps(2, 1), [1.75, 1.5, 1.25]);
    });

    test('1x→3x 逐级到 2.75 为止', () {
      expect(PlaybackSpeedPolicy.rampSteps(1, 3), [1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75]);
    });

    test('小跨度 1x→1.5x 只有一档中间值', () {
      expect(PlaybackSpeedPolicy.rampSteps(1, 1.5), [1.25]);
    });

    test('跨度不足一步时无中间值（调用方直接跳变阈值 .5）', () {
      expect(PlaybackSpeedPolicy.rampSteps(1, 1.2), const <double>[]);
      expect(PlaybackSpeedPolicy.rampSteps(1.75, 1.5), const <double>[]);
    });

    test('步长不能整除时不会越过目标（1x→2.4x）', () {
      expect(PlaybackSpeedPolicy.rampSteps(1, 2.4), [1.25, 1.5, 1.75, 2, 2.25]);
    });
  });
}
