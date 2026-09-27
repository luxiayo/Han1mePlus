import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_plus/src/core/settings.dart';
import 'package:han1me_plus/src/domain/models/video.dart';
import 'package:han1me_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_plus/src/features/shared/compact_video_card.dart';
import 'package:han1me_plus/src/features/shared/video_card.dart';

const _longTitle = '这是一个非常长的两行标题用来验证第二行文字是否被裁切显示不完整的测试文本';

class _FixedSettings extends SettingsController {
  _FixedSettings(this._settings);
  final AppSettings _settings;
  @override
  Future<AppSettings> build() async => _settings;
}

Future<void> _pumpShot(WidgetTester tester, String name, double width, Widget child, {AppSettings settings = const AppSettings()}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(() => _FixedSettings(settings))],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 2));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
}

void main() {
  final videos = List.generate(
    6,
    (i) => VideoCard(
      id: '$i',
      title: _longTitle,
      coverUrl: 'https://example.invalid/$i.jpg',
      artist: '作者名称',
      uploadTime: '2026-09-27',
      rating: '1234',
      duration: '12:34',
    ),
  );
  final diag = Platform.environment.containsKey('DIAG_CARDS');

  testWidgets('grid horizontal (search 默认)', (tester) async {
    await _pumpShot(tester, 'grid_horizontal', 390, VideoCardGrid(videos: videos));
  }, skip: !diag);

  testWidgets('grid vertical', (tester) async {
    await _pumpShot(
      tester,
      'grid_vertical',
      390,
      VideoCardGrid(videos: videos),
      settings: const AppSettings(useHorizontalSearchCards: false),
    );
  }, skip: !diag);

  testWidgets('row vertical (home 132)', (tester) async {
    await _pumpShot(
      tester,
      'row_vertical',
      390,
      SizedBox(
        height: 132 / .58,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [for (final v in videos) SizedBox(width: 132, child: VideoCardTile(video: v))],
        ),
      ),
    );
  }, skip: !diag);

  testWidgets('row horizontal (home 154)', (tester) async {
    final h = 154 * 9 / 16 + videoCardMetaHeightFor(TextScaler.noScaling);
    await _pumpShot(
      tester,
      'row_horizontal',
      390,
      SizedBox(
        height: h,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [for (final v in videos) SizedBox(width: 154, child: VideoCardTile(video: v, horizontal: true))],
        ),
      ),
    );
  }, skip: !diag);

  testWidgets('compact grid', (tester) async {
    await _pumpShot(tester, 'grid_compact', 390, CompactVideoCardGrid(videos: videos));
  }, skip: !diag);
}
