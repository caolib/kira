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
  });
}
