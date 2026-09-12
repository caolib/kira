import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/setting_action_tile.dart';
import 'package:kira/widgets/setting_tile_group.dart';

import '../test_helpers.dart';

/// [SettingTileGroup] 的横向布局:导出/导入、仓库/反馈/日志 这类并排动作行。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpGroup(
    WidgetTester tester, {
    required Axis axis,
    int count = 2,
    double width = 400,
  }) {
    return tester.pumpWidget(
      wrapWithApp(
        Center(
          child: SizedBox(
            width: width,
            child: SettingTileGroup(
              axis: axis,
              children: [
                for (var i = 0; i < count; i++)
                  SettingActionTile(
                    icon: const Icon(Icons.star),
                    label: 'Item $i',
                    onTap: () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('horizontal tiles sit side by side at equal widths', (
    tester,
  ) async {
    await pumpGroup(tester, axis: Axis.horizontal);

    final a = tester.getRect(find.byType(SettingActionTile).at(0));
    final b = tester.getRect(find.byType(SettingActionTile).at(1));

    // 并排:同一行(纵向位置一致),横向不重叠且按顺序排列。
    expect(a.top, closeTo(b.top, 0.01));
    expect(a.height, closeTo(b.height, 0.01));
    expect(a.width, closeTo(b.width, 0.01));
    expect(a.right, lessThanOrEqualTo(b.left + 0.01));
  });

  testWidgets('vertical tiles stack instead', (tester) async {
    await pumpGroup(tester, axis: Axis.vertical);

    final a = tester.getRect(find.byType(SettingActionTile).at(0));
    final b = tester.getRect(find.byType(SettingActionTile).at(1));

    expect(a.bottom, lessThanOrEqualTo(b.top + 0.01));
    expect(a.left, closeTo(b.left, 0.01));
  });

  testWidgets('horizontal row does not overflow at three items', (
    tester,
  ) async {
    // 关于页的「仓库 / 反馈 / 日志」是三项;窄屏下也不应溢出。
    await pumpGroup(tester, axis: Axis.horizontal, count: 3, width: 320);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long labels ellipsize instead of overflowing', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        Center(
          child: SizedBox(
            width: 240,
            child: SettingTileGroup(
              axis: Axis.horizontal,
              children: [
                SettingActionTile(
                  icon: const Icon(Icons.star),
                  label: '一个非常非常长的标签名称需要被截断',
                  onTap: () {},
                ),
                SettingActionTile(
                  icon: const Icon(Icons.star),
                  label: '短',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.every((t) => t.overflow == TextOverflow.ellipsis), isTrue);
  });

  testWidgets('tapping a tile fires its callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrapWithApp(
        Center(
          child: SizedBox(
            width: 400,
            child: SettingTileGroup(
              axis: Axis.horizontal,
              children: [
                SettingActionTile(
                  icon: const Icon(Icons.upload_file_rounded),
                  label: '导出设置',
                  onTap: () => taps++,
                ),
                SettingActionTile(
                  icon: const Icon(Icons.download_for_offline_rounded),
                  label: '导入设置',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('导出设置'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('corner radii follow outer/inner ladder for a row', (
    tester,
  ) async {
    await pumpGroup(tester, axis: Axis.horizontal, count: 3);

    final materials = tester
        .widgetList<Material>(
          find.descendant(
            of: find.byType(SettingTileGroup),
            matching: find.byType(Material),
          ),
        )
        .where((m) => m.borderRadius != null)
        .toList();

    expect(materials, hasLength(3));
    // 首尾外侧用 outerRadius(lg=16),中间内侧用 innerRadius(xs=4)。
    expect(
      materials[0].borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
        topRight: Radius.circular(4),
        bottomRight: Radius.circular(4),
      ),
    );
    expect(
      materials[1].borderRadius,
      const BorderRadius.horizontal(
        left: Radius.circular(4),
        right: Radius.circular(4),
      ),
    );
    expect(
      materials[2].borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(4),
        bottomLeft: Radius.circular(4),
        topRight: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
    );
  });
}
