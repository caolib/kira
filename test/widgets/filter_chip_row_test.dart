import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/filter_chip_row.dart';

import '../test_helpers.dart';

const _tags = [
  FilterTagOption(name: '奇幻', pathWord: 'fantasy', count: 28),
  FilterTagOption(name: '校园生活', pathWord: 'school', count: 1234),
  FilterTagOption(name: '推理', pathWord: 'mystery'),
  FilterTagOption(name: '异世界冒险', pathWord: 'adventure', count: 42),
  FilterTagOption(name: '恋爱', pathWord: 'romance', count: 9),
  FilterTagOption(name: '科幻', pathWord: 'science'),
];

Future<void> _pumpTags(
  WidgetTester tester, {
  required double width,
  List<FilterTagOption> tags = _tags,
  bool justified = true,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  Brightness brightness = Brightness.light,
  String? selectedTag,
  ValueChanged<String?>? onSelected,
}) async {
  await tester.pumpWidget(
    wrapWithApp(
      Theme(
        data: ThemeData(brightness: brightness),
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: Directionality(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: justified
                      ? AllTagsGrid(
                          tags: tags,
                          selectedTag: selectedTag,
                          onSelected: onSelected ?? (_) {},
                        )
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final tag in [
                              const FilterTagOption(name: '全部', pathWord: ''),
                              ...tags,
                            ])
                              FilterChip(
                                label: Text.rich(
                                  TextSpan(
                                    text: tag.name,
                                    children: [
                                      if (tag.count > 0)
                                        TextSpan(
                                          text: ' ${tag.count}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                selected: tag.pathWord.isEmpty,
                                showCheckmark: false,
                                onSelected: (_) {},
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

List<Rect> _chipRects(WidgetTester tester) => [
  for (final element in find.byType(FilterChip).evaluate())
    tester.getRect(find.byWidget(element.widget)),
];

void _expectJustifiedRows(
  WidgetTester tester,
  List<Rect> natural,
  double width, {
  TextDirection direction = TextDirection.ltr,
}) {
  final actual = _chipRects(tester);
  expect(actual, hasLength(natural.length));
  final bounds = tester.getRect(find.byType(AllTagsGrid));
  final rows = <List<int>>[];
  var occupied = 0.0;
  for (var i = 0; i < natural.length; i++) {
    if (rows.isEmpty || occupied + 8 + natural[i].width > width) {
      rows.add([]);
      occupied = 0;
    }
    if (rows.last.isNotEmpty) occupied += 8;
    rows.last.add(i);
    occupied += natural[i].width;
  }
  var top = bounds.top;
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final naturalWidth = row.fold<double>(
      8.0 * (row.length - 1),
      (sum, i) => sum + natural[i].width,
    );
    final extra = r == rows.length - 1
        ? 0.0
        : (width - naturalWidth) / row.length;
    var x = 0.0;
    var rowHeight = 0.0;
    for (final i in row) {
      final expectedWidth = natural[i].width + extra;
      expect(actual[i].width, closeTo(expectedWidth, 0.001));
      expect(actual[i].height, closeTo(natural[i].height, 0.001));
      expect(actual[i].top, closeTo(top, 0.001));
      expect(
        actual[i].left,
        closeTo(
          direction == TextDirection.ltr
              ? bounds.left + x
              : bounds.right - x - expectedWidth,
          0.001,
        ),
      );
      // 不能只是外层占位变宽：实际 Material 边框也必须撑满。
      final chip = find.byType(FilterChip).at(i);
      final material = find.descendant(
        of: chip,
        matching: find.byType(Material),
      );
      expect(tester.getRect(material).width, closeTo(expectedWidth, 0.001));
      final label = find.descendant(of: chip, matching: find.byType(Text));
      expect(
        tester.getRect(label).center.dx,
        closeTo(actual[i].center.dx, 0.001),
      );
      x += expectedWidth + 8;
      if (actual[i].height > rowHeight) rowHeight = actual[i].height;
    }
    top += rowHeight + 8;
  }
  expect(bounds.height, closeTo(top - bounds.top - 8, 0.001));
}

void main() {
  setUp(setupSecureCredentialStoreForTest);
  tearDown(teardownSecureCredentialStoreForTest);

  testWidgets('filter chip stays compact and responds at the top edge', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      wrapWithApp(
        Align(
          alignment: Alignment.topLeft,
          child: FilterChipRow(
            options: const [FilterChipOption(label: '全部', value: '')],
            onTap: (option) => selected = option.value,
          ),
        ),
      ),
    );
    final chip = find.byType(FilterChip);
    final rect = tester.getRect(chip);
    // 紧凑档（shrinkWrap）：与热门搜索关键字同高，低于 48dp 触控建议值。
    expect(rect.height, allOf(greaterThanOrEqualTo(38), lessThan(48)));
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    expect(selected, '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter row grows with large text and the reset keeps working', (
    tester,
  ) async {
    var reset = 0;
    await tester.pumpWidget(
      wrapWithApp(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(3)),
            child: Align(
              alignment: Alignment.topLeft,
              child: FilterChipRow(
                options: const [FilterChipOption(label: '爱情', value: 'love')],
                onTap: (_) {},
                trailing: FilterRowResetButton(
                  icon: Icons.refresh,
                  label: '重置',
                  onPressed: () => reset++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final chip = find.widgetWithText(FilterChip, '爱情');
    expect(tester.getSize(chip).height, greaterThan(48));
    final resetButton = find.byType(FilterRowResetButton);
    expect(tester.getSize(resetButton).height, greaterThan(48));
    await tester.tap(resetButton);
    expect(reset, 1);
    expect(tester.takeException(), isNull);
  });

  for (final config in [
    (width: 280.0, scale: 1.0, brightness: Brightness.light),
    (width: 375.0, scale: 1.0, brightness: Brightness.light),
    (width: 760.0, scale: 1.0, brightness: Brightness.light),
    (width: 320.0, scale: 2.0, brightness: Brightness.dark),
    (width: 375.0, scale: 3.0, brightness: Brightness.light),
  ]) {
    testWidgets('expanded tags justify non-final rows at $config', (
      tester,
    ) async {
      await _pumpTags(
        tester,
        width: config.width,
        justified: false,
        textScale: config.scale,
        brightness: config.brightness,
      );
      final natural = _chipRects(tester);
      await _pumpTags(
        tester,
        width: config.width,
        textScale: config.scale,
        brightness: config.brightness,
      );
      _expectJustifiedRows(tester, natural, config.width);
      final box = tester.renderObject<RenderBox>(find.byType(AllTagsGrid));
      expect(
        box.getDryLayout(BoxConstraints.tightFor(width: config.width)),
        box.size,
      );
    });
  }

  testWidgets('a single row or only the all tag keeps its natural width', (
    tester,
  ) async {
    for (final tags in [
      <FilterTagOption>[],
      [_tags.first],
    ]) {
      await _pumpTags(tester, width: 700, tags: tags, justified: false);
      final natural = _chipRects(tester);
      await _pumpTags(tester, width: 700, tags: tags);
      _expectJustifiedRows(tester, natural, 700);
      expect(_chipRects(tester).last.right, lessThan(700));
    }
  });

  testWidgets('tags reflow after resizing and changing direction', (
    tester,
  ) async {
    await _pumpTags(tester, width: 300, justified: false);
    final natural = _chipRects(tester);
    await _pumpTags(tester, width: 700);
    await _pumpTags(tester, width: 300);
    _expectJustifiedRows(tester, natural, 300);
    await _pumpTags(tester, width: 300, direction: TextDirection.rtl);
    _expectJustifiedRows(tester, natural, 300, direction: TextDirection.rtl);
  });

  testWidgets('long labels stay within narrow constraints', (tester) async {
    await _pumpTags(
      tester,
      width: 160,
      textScale: 3,
      tags: const [
        FilterTagOption(
          name: '这是一个非常长的题材名称',
          pathWord: 'long',
          count: 100000000,
        ),
        FilterTagOption(name: '科幻', pathWord: 'science'),
      ],
    );
    final bounds = tester.getRect(find.byType(AllTagsGrid));
    for (final rect in _chipRects(tester)) {
      expect(rect.left, greaterThanOrEqualTo(bounds.left));
      expect(rect.right, lessThanOrEqualTo(bounds.right));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded padding is clickable and keyboard selection works', (
    tester,
  ) async {
    String? selected;
    await _pumpTags(
      tester,
      width: 300,
      selectedTag: 'fantasy',
      onSelected: (value) => selected = value,
    );
    final chip = find.byType(FilterChip).at(1);
    expect(tester.widget<FilterChip>(chip).selected, isTrue);
    final rect = tester.getRect(chip);
    await tester.tapAt(Offset(rect.right - 2, rect.center.dy));
    expect(selected, 'fantasy');
    // 无鼠标操作时，Tab 顺序仍跟随 tag 的原顺序。
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tag toggle has a border and preserves expand/collapse actions', (
    tester,
  ) async {
    var expanded = false;
    await tester.pumpWidget(
      wrapWithApp(
        StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.topLeft,
            child: FilterTagsToggleButton(
              expanded: expanded,
              onPressed: () => setState(() => expanded = !expanded),
            ),
          ),
        ),
      ),
    );
    final chip = find.byType(ActionChip);
    final material = tester.widget<Material>(
      find.descendant(of: chip, matching: find.byType(Material)),
    );
    expect((material.shape! as OutlinedBorder).side.style, BorderStyle.solid);
    expect(
      tester.getSize(chip).height,
      allOf(greaterThanOrEqualTo(38), lessThan(48)),
    );
    expect(find.byIcon(Icons.expand_more), findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(expanded, isTrue);
    expect(find.byIcon(Icons.expand_less), findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(expanded, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded tags keep the same compact height', (tester) async {
    String? selected;
    await tester.pumpWidget(
      wrapWithApp(
        AllTagsGrid(
          tags: const [FilterTagOption(name: '奇幻', pathWord: 'fantasy')],
          selectedTag: null,
          onSelected: (value) => selected = value,
        ),
      ),
    );
    final chip = find.widgetWithText(FilterChip, '奇幻');
    final rect = tester.getRect(chip);
    expect(rect.height, allOf(greaterThanOrEqualTo(38), lessThan(48)));
    await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
    expect(selected, 'fantasy');
    expect(tester.takeException(), isNull);
  });
}
