import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/remote_notice.dart';
import '../models/user_manager.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/app_logger.dart';
import '../utils/remote_notice_service.dart';
import '../utils/time_format.dart';
import '../utils/toast.dart';

class NoticeCenterPage extends StatefulWidget {
  const NoticeCenterPage({super.key, RemoteNoticeService? service})
    : _service = service;

  final RemoteNoticeService? _service;

  @override
  State<NoticeCenterPage> createState() => _NoticeCenterPageState();
}

class _NoticeCenterPageState extends State<NoticeCenterPage> {
  late final RemoteNoticeService _service =
      widget._service ?? RemoteNoticeService();
  final _user = UserManager();

  List<RemoteNotice> _notices = const [];
  Set<String> _seenKeys = const {};
  Set<String> _expandedSeenKeys = const {};
  bool _loading = true;
  bool _refreshing = false;
  bool _expiredExpanded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    unawaited(_load(refreshRemote: true));
  }

  @override
  void dispose() {
    _user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load({bool refreshRemote = false}) async {
    if (!mounted) return;
    setState(() {
      if (refreshRemote) {
        _refreshing = true;
      } else {
        _loading = true;
      }
      _error = null;
    });

    try {
      final result = await _service.sync();
      final seenKeys = await _service.loadSeenKeys();
      if (!mounted) return;
      setState(() {
        _notices = result.notices;
        _seenKeys = seenKeys;
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'notice_center',
        ),
      );
      if (!mounted) return;
      RemoteNoticeService.unreadActiveCount.value = 0;
      setState(() {
        _notices = const [];
        _seenKeys = const {};
        _error = refreshRemote
            ? AppLocalizations.of(context)!.noticeRefreshFailed
            : AppLocalizations.of(context)!.noticeReadFailed;
      });
      if (refreshRemote) {
        showToast(
          context,
          AppLocalizations.of(context)!.noticeRefreshFailed,
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _markAllSeen() async {
    final notices = _activeUnreadNotices().toList();
    if (notices.isEmpty) return;

    await _service.markSeen(notices);
    final seenKeys = await _service.loadSeenKeys();
    await _service.updateUnreadActiveCount(_notices);
    if (!mounted) return;
    setState(() {
      _seenKeys = seenKeys;
    });
    showToast(context, AppLocalizations.of(context)!.noticeAllMarkedRead);
  }

  Future<void> _handleNoticeTap(RemoteNotice notice) async {
    final seenKey = RemoteNoticeService.seenKeyFor(notice);
    if (!_seenKeys.contains(seenKey)) {
      await _service.markSeen([notice]);
      final seenKeys = await _service.loadSeenKeys();
      await _service.updateUnreadActiveCount(_notices);
      if (!mounted) return;
      setState(() {
        _seenKeys = seenKeys;
        _expandedSeenKeys = {..._expandedSeenKeys, seenKey};
      });
      return;
    }

    setState(() {
      final next = {..._expandedSeenKeys};
      if (!next.add(seenKey)) {
        next.remove(seenKey);
      }
      _expandedSeenKeys = next;
    });
  }

  Future<void> _openNoticeSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final l10n = AppLocalizations.of(context)!;
          final tt = Theme.of(context).textTheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: Text(l10n.remoteNoticeTitle),
                subtitle: Text(l10n.remoteNoticeDesc, style: tt.bodySmall),
                value: _user.remoteNoticeEnabled,
                onChanged: (value) async {
                  await _user.setRemoteNoticeEnabled(value);
                  setModalState(() {});
                },
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount = _activeUnreadNotices().length;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.noticeCenterTitle),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context)!.noticeSettingsTooltip,
            onPressed: _openNoticeSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          if (unreadCount > 0)
            IconButton(
              tooltip: AppLocalizations.of(context)!.noticeMarkAllReadTooltip,
              onPressed: _markAllSeen,
              icon: const Icon(Icons.done_all_rounded),
            ),
          IconButton(
            tooltip: AppLocalizations.of(context)!.noticeRefreshTooltip,
            onPressed: _refreshing ? null : () => _load(refreshRemote: true),
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _notices.isEmpty) {
      return const Center(child: ExpressiveLoadingIndicator());
    }

    final error = _error;
    if (error != null && _notices.isEmpty) {
      return _NoticeEmptyState(
        icon: Icons.error_outline_rounded,
        title: error,
        actionLabel: AppLocalizations.of(context)!.retryButton,
        onAction: () => _load(refreshRemote: true),
      );
    }

    if (_notices.isEmpty) {
      return _NoticeEmptyState(
        icon: Icons.notifications_none_rounded,
        title: AppLocalizations.of(context)!.noticeEmptyTitle,
        actionLabel: AppLocalizations.of(context)!.refreshButton,
        onAction: () => _load(refreshRemote: true),
      );
    }

    final now = DateTime.now();
    final active = <RemoteNotice>[];
    final expired = <RemoteNotice>[];
    for (final notice in _notices) {
      if (!notice.isActive(now)) {
        expired.add(notice);
      } else {
        active.add(notice);
      }
    }
    active.sort(RemoteNotice.compareForTimeline);
    expired.sort(RemoteNotice.compareForTimeline);

    return RefreshIndicator(
      onRefresh: () => _load(refreshRemote: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          ..._buildNoticeItems(active),
          if (expired.isNotEmpty)
            _NoticeFoldSection(
              title: AppLocalizations.of(context)!.noticeExpiredTitle,
              count: expired.length,
              expanded: _expiredExpanded,
              onToggle: () {
                setState(() {
                  _expiredExpanded = !_expiredExpanded;
                });
              },
              children: _buildNoticeItems(expired),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildNoticeItems(List<RemoteNotice> notices) {
    return [
      for (var i = 0; i < notices.length; i++) ...[
        Builder(
          builder: (context) {
            final notice = notices[i];
            final seenKey = RemoteNoticeService.seenKeyFor(notice);
            final unread = _isUnreadActive(notice);
            return _NoticeTimelineItem(
              notice: notice,
              unread: unread,
              expanded: unread || _expandedSeenKeys.contains(seenKey),
              first: i == 0,
              last: i == notices.length - 1,
              onTap: () => _handleNoticeTap(notice),
            );
          },
        ),
      ],
    ];
  }

  bool _isSeen(RemoteNotice notice) {
    return _seenKeys.contains(RemoteNoticeService.seenKeyFor(notice));
  }

  bool _isUnreadActive(RemoteNotice notice) {
    return notice.isActive(DateTime.now()) && !_isSeen(notice);
  }

  Iterable<RemoteNotice> _activeUnreadNotices() {
    return _notices.where(_isUnreadActive);
  }
}

class _NoticeFoldSection extends StatelessWidget {
  const _NoticeFoldSection({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(top: 4, bottom: expanded ? 8 : 12),
      child: Column(
        children: [
          InkWell(
            borderRadius: AppRadius.smR,
            onTap: onToggle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: AppRadius.smR,
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '$count',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[const SizedBox(height: AppSpacing.md), ...children],
        ],
      ),
    );
  }
}

class _NoticeEmptyState extends StatelessWidget {
  const _NoticeEmptyState({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeTimelineItem extends StatelessWidget {
  const _NoticeTimelineItem({
    required this.notice,
    required this.unread,
    required this.expanded,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final RemoteNotice notice;
  final bool unread;
  final bool expanded;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = _noticeVisualStyle(Theme.of(context).colorScheme, notice);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Expanded(child: _TimelineLine(visible: !first)),
                _TimelineDot(notice: notice),
                Expanded(child: _TimelineLine(visible: !last)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                color: style.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.mdR,
                  side: BorderSide(color: style.border, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          unread ? 32 : 16,
                          16,
                        ),
                        child: _NoticeContent(
                          notice: notice,
                          expanded: expanded,
                        ),
                      ),
                      if (unread)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: _UnreadDot(
                            noticeId: notice.id,
                            color: style.accent,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineLine extends StatelessWidget {
  const _TimelineLine({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      width: 2,
      margin: const EdgeInsets.symmetric(horizontal: 15),
      color: visible ? color.withValues(alpha: 0.7) : Colors.transparent,
    );
  }
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.notice});

  final RemoteNotice notice;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _noticeAccentColor(cs, notice);
    final dot = Container(
      width: notice.isPinned ? 15 : 14,
      height: notice.isPinned ? 15 : 14,
      decoration: BoxDecoration(
        color: cs.surface,
        shape: notice.isPinned ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: notice.isPinned ? BorderRadius.circular(3) : null,
        border: Border.all(color: color, width: 2),
      ),
    );

    return Semantics(
      label: notice.isPinned
          ? AppLocalizations.of(context)!.noticePinnedNodeSemantics
          : AppLocalizations.of(context)!.noticeNodeSemantics,
      child: notice.isPinned
          ? Transform.rotate(angle: 0.785398, child: dot)
          : dot,
    );
  }
}

class _NoticeContent extends StatelessWidget {
  const _NoticeContent({required this.notice, required this.expanded});

  final RemoteNotice notice;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final style = _noticeVisualStyle(cs, notice);
    final active = notice.isActive(DateTime.now());
    final hasBadges = !active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: style.iconSurface,
                borderRadius: AppRadius.smR,
              ),
              child: Icon(style.icon, size: 17, color: style.accent),
            ),
            Expanded(
              child: Text(
                notice.title,
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: style.titleColor,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              TimeFormat.relative(
                notice.publishedAt,
                AppLocalizations.of(context)!,
              ),
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        if (hasBadges) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [if (!active) const _ExpiredChip()],
          ),
        ],
        if (expanded) ...[
          const SizedBox(height: AppSpacing.md),
          _NoticePlainText(data: notice.content, linkColor: style.accent),
          if (notice.url != null) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _openUrl(notice.url!),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(AppLocalizations.of(context)!.noticeOpenLink),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.noticeId, required this.color});

  final String noticeId;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context)!.noticeUnreadSemantics,
      child: Container(
        key: ValueKey('notice-unread-dot-$noticeId'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 4),
          ],
        ),
      ),
    );
  }
}

class _ExpiredChip extends StatelessWidget {
  const _ExpiredChip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppRadius.fullR,
      ),
      child: Text(
        AppLocalizations.of(context)!.noticeExpiredBadge,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

Future<void> _openUrl(String rawUrl) async {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _NoticePlainText extends StatefulWidget {
  const _NoticePlainText({required this.data, required this.linkColor});

  final String data;
  final Color linkColor;

  @override
  State<_NoticePlainText> createState() => _NoticePlainTextState();
}

class _NoticePlainTextState extends State<_NoticePlainText> {
  late List<_NoticeTextSegment> _segments;

  @override
  void initState() {
    super.initState();
    _segments = _parseNoticeText(widget.data);
  }

  @override
  void didUpdateWidget(_NoticePlainText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      for (final segment in _segments) {
        segment.recognizer?.dispose();
      }
      _segments = _parseNoticeText(widget.data);
    }
  }

  @override
  void dispose() {
    for (final segment in _segments) {
      segment.recognizer?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final baseStyle = tt.bodyMedium?.copyWith(
      color: cs.onSurface,
      height: 1.55,
    );

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: [
          for (final segment in _segments)
            TextSpan(
              text: segment.text,
              style: segment.isLink
                  ? baseStyle?.copyWith(
                      color: widget.linkColor,
                      decoration: TextDecoration.underline,
                      decorationColor: widget.linkColor,
                      fontWeight: FontWeight.w600,
                    )
                  : baseStyle,
              recognizer: segment.recognizer,
            ),
        ],
      ),
    );
  }
}

class _NoticeTextSegment {
  _NoticeTextSegment.text(this.text) : recognizer = null;

  _NoticeTextSegment.link(this.text)
    : recognizer = (TapGestureRecognizer()..onTap = (() => _openUrl(text)));

  final String text;
  final TapGestureRecognizer? recognizer;

  bool get isLink => recognizer != null;
}

final _noticeUrlPattern = RegExp(r"""https?://[^\s<>"']+""");
final _noticeTrailingPunctuation = RegExp(r'[.,!?;:，。！？；：、\)\]）】]+$');

List<_NoticeTextSegment> _parseNoticeText(String data) {
  final segments = <_NoticeTextSegment>[];
  var index = 0;

  for (final match in _noticeUrlPattern.allMatches(data)) {
    if (match.start > index) {
      segments.add(_NoticeTextSegment.text(data.substring(index, match.start)));
    }

    final rawUrl = match.group(0)!;
    final punctuationMatch = _noticeTrailingPunctuation.firstMatch(rawUrl);
    final punctuation = punctuationMatch?.group(0) ?? '';
    final url = punctuation.isEmpty
        ? rawUrl
        : rawUrl.substring(0, rawUrl.length - punctuation.length);

    if (url.isNotEmpty) {
      segments.add(_NoticeTextSegment.link(url));
    }
    if (punctuation.isNotEmpty) {
      segments.add(_NoticeTextSegment.text(punctuation));
    }
    index = match.end;
  }

  if (index < data.length) {
    segments.add(_NoticeTextSegment.text(data.substring(index)));
  }
  if (segments.isEmpty) {
    segments.add(_NoticeTextSegment.text(data));
  }
  return segments;
}

class _NoticeVisualStyle {
  const _NoticeVisualStyle({
    required this.accent,
    required this.border,
    required this.surface,
    required this.iconSurface,
    required this.titleColor,
    required this.icon,
  });

  final Color accent;
  final Color border;
  final Color surface;
  final Color iconSurface;
  final Color titleColor;
  final IconData icon;
}

_NoticeVisualStyle _noticeVisualStyle(ColorScheme cs, RemoteNotice notice) {
  final dark = cs.brightness == Brightness.dark;
  final (accent, icon) = switch (notice.type) {
    RemoteNoticeType.tip => (
      dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32),
      Icons.lightbulb_outline,
    ),
    RemoteNoticeType.warning => (
      dark ? const Color(0xFFFFB74D) : const Color(0xFFEF6C00),
      Icons.warning_amber_rounded,
    ),
    RemoteNoticeType.important => (
      dark ? const Color(0xFFBA68C8) : const Color(0xFF7B1FA2),
      Icons.priority_high_rounded,
    ),
    RemoteNoticeType.caution => (cs.error, Icons.report_gmailerrorred_rounded),
    RemoteNoticeType.note => (cs.primary, Icons.info_outline_rounded),
  };
  final surfaceAlpha = dark ? 0.10 : 0.045;
  final iconSurfaceAlpha = dark ? 0.18 : 0.11;

  return _NoticeVisualStyle(
    accent: accent,
    border: accent,
    // Preserve the translucent-tint appearance without letting an elevation
    // shadow show through the card's interior.
    surface: Color.alphaBlend(
      accent.withValues(alpha: surfaceAlpha),
      cs.surface,
    ),
    iconSurface: accent.withValues(alpha: iconSurfaceAlpha),
    titleColor: cs.onSurface,
    icon: icon,
  );
}

Color _noticeAccentColor(ColorScheme cs, RemoteNotice notice) {
  return _noticeVisualStyle(cs, notice).accent;
}
