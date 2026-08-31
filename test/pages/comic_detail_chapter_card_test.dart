import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/pages/comic_detail_page.dart';

import '../test_helpers.dart';

void main() {
  test('chapterTileExtent 默认与缩小字号时保持 52 下限', () {
    expect(chapterTileExtent(1.0), 52);
    expect(chapterTileExtent(0.85), 52);
  });

  test('chapterTileExtent 在溢出临界点之后随字号增长', () {
    // 内容高度 ≈ 14 + 33.5s，s≈1.14 起超过 52；1.25 对应 Windows 常见 125% 缩放
    expect(chapterTileExtent(1.25), greaterThan(52));
    expect(chapterTileExtent(1.5), greaterThan(chapterTileExtent(1.25)));
  });

  group('comicDetailUsesTwoPane 横竖屏断点', () {
    test('竖屏手机不分栏', () {
      expect(comicDetailUsesTwoPane(const Size(360, 800)), isFalse);
      expect(comicDetailUsesTwoPane(const Size(412, 915)), isFalse);
    });

    test('窄于 640 的横屏不分栏（避免小屏分栏后两侧都太挤）', () {
      expect(comicDetailUsesTwoPane(const Size(639, 360)), isFalse);
    });

    test('宽 ≥640 且宽 > 高时分栏', () {
      expect(comicDetailUsesTwoPane(const Size(640, 360)), isTrue);
      expect(comicDetailUsesTwoPane(const Size(1280, 720)), isTrue);
      expect(comicDetailUsesTwoPane(const Size(1920, 1080)), isTrue);
    });

    test('正方形/接近正方形不分栏', () {
      expect(comicDetailUsesTwoPane(const Size(800, 800)), isFalse);
    });
  });

  group('comicDetailInfoPaneWidth 左栏宽度', () {
    test('夹在 300~420 之间并随窗口增长', () {
      expect(comicDetailInfoPaneWidth(const Size(640, 360)), 300);
      expect(comicDetailInfoPaneWidth(const Size(1000, 500)), 360);
      expect(comicDetailInfoPaneWidth(const Size(1280, 720)), 420);
      expect(comicDetailInfoPaneWidth(const Size(1920, 1080)), 420);
    });
  });

  for (final scale in [1.0, 1.25, 1.5]) {
    testWidgets('ChapterCard 在 ${scale}x 文字缩放下不纵向溢出', (tester) async {
      await tester.pumpWidget(
        wrapWithApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Center(
                child: SizedBox(
                  // 窄列（maxCrossAxisExtent 150 / 宽屏多列）下的典型卡片宽度
                  width: 136,
                  height: chapterTileExtent(scale),
                  child: ChapterCard(
                    name: '第277话 试看',
                    subtitle: '已读 · 33P',
                    isSelected: false,
                    isLastRead: true,
                    isRead: true,
                    isDownloaded: false,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('第277话 试看'), findsOneWidget);
    });
  }
}
