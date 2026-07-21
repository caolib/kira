import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(meta.icon, size: 18, color: meta.color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  meta.label,
                  style: tt.labelMedium?.copyWith(
                    color: meta.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (content.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  MarkdownBody(
                    data: content,
                    onTapLink: onTapLink ?? _openMarkdownLink,
                    styleSheet: styleSheet.copyWith(
                      p: styleSheet.p?.copyWith(color: cs.onSurface),
                      a: styleSheet.a?.copyWith(color: meta.color),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
