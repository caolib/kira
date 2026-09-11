import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/github_markdown.dart';

void main() {
  testWidgets('renders GitHub style alert blocks inside markdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GitHubMarkdown(
            data: '''
## 标题

> [!WARNING]
> 支持 **Markdown** 警告框

- 普通列表
''',
          ),
        ),
      ),
    );

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('Warning'), findsOneWidget);
    expect(find.textContaining('支持'), findsOneWidget);
    expect(find.textContaining('普通列表'), findsOneWidget);
    // 沿用 markdown 库默认缩进(24)：bullet 列 = 24 + 内边距 4 → 正文起始 x = 28。
    expect(tester.getTopLeft(find.text('普通列表')).dx, closeTo(28, 0.5));
  });

  testWidgets('renders 「text」 as a highlight chip inside its alert box', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GitHubMarkdown(
            data: '''
> [!TIP]
> - 新增「Windows 桌面版」（beta）
''',
          ),
        ),
      ),
    );

    final textFinder = find.text('Windows 桌面版');
    expect(textFinder, findsOneWidget);
    // 前景白色。
    final text = tester.widget<Text>(textFinder);
    expect(text.style?.color, Colors.white);

    // 背景为所在警告框的主题色（TIP 绿）。
    final container = tester.widget<Container>(
      find.ancestor(of: textFinder, matching: find.byType(Container)).first,
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      const Color(0xFF1A7F37),
    );
  });

  testWidgets('renders top-level 「text」 with the warning fallback color', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: GitHubMarkdown(data: '外面的「标签」文本')),
      ),
    );

    final textFinder = find.text('标签');
    expect(textFinder, findsOneWidget);
    final container = tester.widget<Container>(
      find.ancestor(of: textFinder, matching: find.byType(Container)).first,
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      const Color(0xFF9A6700),
    );
  });
}
