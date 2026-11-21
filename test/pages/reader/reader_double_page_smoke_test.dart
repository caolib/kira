import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/user_manager.dart';
import 'package:kira/pages/reader_page.dart';
import 'package:kira/utils/double_page_layout.dart';

/// 编译级冒烟测试：把阅读器整条代码路径（含全部 part 文件）与用户设置
/// 模型一起拉进编译，确认双页阅读引入的符号在真实编译下成立。
void main() {
  test('阅读器与用户设置模型可编译', () {
    expect(ReaderPage, isNotNull);
    expect(UserManager, isNotNull);
    expect(DoublePageLayout, isNotNull);
  });

  test('双页布局在真实运行时按预期分组', () {
    final layout = DoublePageLayout.fromPageCounts([3]);
    expect(layout.spreadCount, 2);
    expect(layout.pagesInSpread(0), [(chapterIndex: 0, imageIndex: 0)]);
    expect(layout.pagesInSpread(1), [
      (chapterIndex: 0, imageIndex: 1),
      (chapterIndex: 0, imageIndex: 2),
    ]);
  });

  testWidgets('阅读器可被构造', (tester) async {
    const page = ReaderPage(
      pathWord: 'smoke-comic',
      chapterUuid: 'smoke-chapter',
      chapterName: '第 1 话',
    );
    expect(page, isA<StatefulWidget>());
    expect(page.initialPage, 1);
    expect(page.noCatalogBelow, isFalse);
  });
}
