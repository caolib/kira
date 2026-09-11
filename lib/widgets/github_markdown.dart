import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class GitHubMarkdown extends StatelessWidget {
  const GitHubMarkdown({
    super.key,
    required this.data,
    this.styleSheet,
    this.onTapLink,
  });

  final String data;
  final MarkdownStyleSheet? styleSheet;
  final void Function(String text, String? href, String title)? onTapLink;

  @override
  Widget build(BuildContext context) {
    final blocks = _parseBlocks(data);
    if (blocks.isEmpty) return const SizedBox.shrink();

    final style = styleSheet ?? githubMarkdownStyleSheet(context);
    // 顶层文本不被任何警告框包裹，高亮块回退到警告色。
    final highlightBuilder = _HighlightBuilder(_alertMetas['WARNING']!.color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          switch (blocks[i]) {
            _MarkdownTextBlock(:final text) => MarkdownBody(
              data: text,
              onTapLink: onTapLink ?? _openMarkdownLink,
              styleSheet: style,
              inlineSyntaxes: [_HighlightSyntax()],
              builders: {_HighlightSyntax.tag: highlightBuilder},
            ),
            _MarkdownAlertBlock(:final type, :final content) => _GitHubAlertBox(
              type: type,
              content: content,
              styleSheet: style,
              onTapLink: onTapLink,
            ),
          },
        ],
      ],
    );
  }
}

MarkdownStyleSheet githubMarkdownStyleSheet(
  BuildContext context, {
  Color? foreground,
}) {
  final cs = Theme.of(context).colorScheme;
  final base = Theme.of(context).textTheme.bodyMedium?.copyWith(
    color: foreground ?? cs.onSurface,
    height: 1.48,
  );

  return MarkdownStyleSheet(
    p: base,
    h1: base?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
    h2: base?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
    h3: base?.copyWith(fontSize: 18, fontWeight: FontWeight.w700),
    h4: base?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
    strong: base?.copyWith(fontWeight: FontWeight.w700),
    em: base?.copyWith(fontStyle: FontStyle.italic),
    a: base?.copyWith(color: cs.primary, decoration: TextDecoration.underline),
    listBullet: base,
    // 不自定义缩进，沿用 markdown 库默认值(24)。
    listIndent: AppSpacing.xxl,
    blockquote: base?.copyWith(color: cs.onSurfaceVariant),
    blockquoteDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      border: Border(left: BorderSide(color: cs.primary, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    code: base?.copyWith(
      fontFamily: 'monospace',
      backgroundColor: cs.surfaceContainerHighest,
    ),
    codeblockDecoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: AppRadius.smR,
    ),
    codeblockPadding: const EdgeInsets.all(12),
  );
}

/// 「文本」→ 高亮块：经 [_HighlightSyntax] 解析为 [tag] 元素，交给 builder 渲染。
class _HighlightSyntax extends md.InlineSyntax {
  static const tag = 'high';

  _HighlightSyntax() : super('「([^「」]+)」');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element(tag, [md.Text(match[1]!)]));
    return true;
  }
}

/// 把 [_HighlightSyntax.tag] 元素渲染成实色背景、白色前景的小高亮块。
/// 背景色取所在警告框的主题色（框外回退值由调用方决定）。
class _HighlightBuilder extends MarkdownElementBuilder {
  _HighlightBuilder(this.backgroundColor);

  final Color backgroundColor;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final base = parentStyle ?? preferredStyle;
    final style =
        base?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          height: 1.3,
          // 比正文小一号，避免白字加粗在色块上显得偏大。
          fontSize: (base.fontSize ?? 14) - 1,
        ) ??
        const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          height: 1.3,
          fontSize: 13,
        );
    return Container(
      // 左右内边距收紧，外间距加大，色块与相邻文字留出呼吸空间。
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: AppRadius.xsR,
      ),
      child: Text(element.textContent, style: style),
    );
  }
}

sealed class _MarkdownBlock {
  const _MarkdownBlock();
}

class _MarkdownTextBlock extends _MarkdownBlock {
  const _MarkdownTextBlock(this.text);

  final String text;
}

class _MarkdownAlertBlock extends _MarkdownBlock {
  const _MarkdownAlertBlock({required this.type, required this.content});

  final String type;
  final String content;
}

class _AlertMeta {
  const _AlertMeta(this.color, this.icon, this.label);

  final Color color;
  final IconData icon;
  final String label;
}

const _alertMetas = <String, _AlertMeta>{
  'NOTE': _AlertMeta(Color(0xFF0969DA), Icons.info_outline, 'Note'),
  'TIP': _AlertMeta(Color(0xFF1A7F37), Icons.lightbulb_outline, 'Tip'),
  'IMPORTANT': _AlertMeta(Color(0xFF8250DF), Icons.bolt_outlined, 'Important'),
  'WARNING': _AlertMeta(
    Color(0xFF9A6700),
    Icons.warning_amber_rounded,
    'Warning',
  ),
  'CAUTION': _AlertMeta(Color(0xFFCF222E), Icons.dangerous_outlined, 'Caution'),
};

final _alertStartRegex = RegExp(
  r'^>\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$',
  caseSensitive: false,
);

List<_MarkdownBlock> _parseBlocks(String data) {
  final lines = data.replaceAll('\r\n', '\n').split('\n');
  final blocks = <_MarkdownBlock>[];
  final pending = <String>[];

  void flushPending() {
    final text = pending.join('\n').trim();
    if (text.isNotEmpty) blocks.add(_MarkdownTextBlock(text));
    pending.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final trimmed = lines[i].trim();
    final alertStart = _alertStartRegex.firstMatch(trimmed);
    if (alertStart == null) {
      pending.add(lines[i]);
      i++;
      continue;
    }

    flushPending();
    final type = alertStart.group(1)!.toUpperCase();
    final content = <String>[];
    i++;
    while (i < lines.length) {
      final line = lines[i];
      final lineTrimmed = line.trim();
      if (_alertStartRegex.hasMatch(lineTrimmed)) break;
      if (lineTrimmed.isEmpty) {
        content.add('');
        i++;
        continue;
      }
      if (!lineTrimmed.startsWith('>')) break;
      content.add(line.replaceFirst(RegExp(r'^\s*>\s?'), ''));
      i++;
    }
    blocks.add(_MarkdownAlertBlock(type: type, content: content.join('\n')));
  }

  flushPending();
  return blocks;
}

class _GitHubAlertBox extends StatelessWidget {
  const _GitHubAlertBox({
    required this.type,
    required this.content,
    required this.styleSheet,
    required this.onTapLink,
  });

  final String type;
  final String content;
  final MarkdownStyleSheet styleSheet;
  final void Function(String text, String? href, String title)? onTapLink;

  @override
  Widget build(BuildContext context) {
    final meta = _alertMetas[type] ?? _alertMetas['NOTE']!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: meta.color, width: 2),
      ),
      // 与 GitHub 网页版一致：图标 + 标题占一行，内容在标题下整行铺开，
      // 这样圆点距左边框 ≈ 容器内边距，而不是被图标列顶到 38px 处。
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(meta.icon, size: 18, color: meta.color),
              const SizedBox(width: AppSpacing.sm),
              Text(
                meta.label,
                style: tt.labelMedium?.copyWith(
                  color: meta.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (content.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            MarkdownBody(
              data: content,
              onTapLink: onTapLink ?? _openMarkdownLink,
              styleSheet: styleSheet.copyWith(
                p: styleSheet.p?.copyWith(color: cs.onSurface),
                // Bold text inside the alert keeps normal weight and
                // adopts the alert color instead of the outer strong.
                strong: styleSheet.p?.copyWith(color: meta.color),
                a: styleSheet.a?.copyWith(color: meta.color),
              ),
              inlineSyntaxes: [_HighlightSyntax()],
              builders: {_HighlightSyntax.tag: _HighlightBuilder(meta.color)},
            ),
          ],
        ],
      ),
    );
  }
}

void _openMarkdownLink(String text, String? href, String title) {
  if (href == null || href.trim().isEmpty) return;
  unawaited(_openUrl(href));
}

Future<void> _openUrl(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
