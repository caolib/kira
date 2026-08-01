part of '../chapter_comments_sheet.dart';

class _CommentSkeleton extends StatefulWidget {
  final bool compact;
  const _CommentSkeleton({required this.compact});

  @override
  State<_CommentSkeleton> createState() => _CommentSkeletonState();
}

class _CommentSkeletonState extends State<_CommentSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final horizontalPadding = widget.compact ? 10.0 : 12.0;
    final topPadding = widget.compact ? 8.0 : 12.0;
    final bottomPadding = widget.compact ? 4.0 : 12.0;
    final avatarSize = widget.compact ? 20.0 : 28.0;

    return FadeTransition(
      opacity: Tween<double>(
        begin: 0.3,
        end: 0.7,
      ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut)),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          bottomPadding,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(_commentCardCornerRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 100,
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    borderRadius: AppRadius.xsR,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              height: widget.compact ? 14 : 16,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: AppRadius.xsR,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: MediaQuery.sizeOf(context).width * 0.6,
              height: widget.compact ? 14 : 16,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.2),
                borderRadius: AppRadius.xsR,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _CommentCard extends StatefulWidget {
  final ChapterCommentDisplayEntry entry;
  final String relativeTime;
  final bool compact;
  final bool showAvatar;
  final bool showUserName;
  final bool showCommentTime;
  final double fontScale;
  final Set<int> spoilerIds;

  /// 长按 / 右键评论时触发（携带触发位置，用于弹出上下文菜单）。
  final void Function(ChapterCommentDisplayEntry entry, Offset position)?
  onLongPress;

  /// 点击合并评论时触发（单条评论不响应点击）。
  final void Function(ChapterCommentDisplayEntry entry)? onTapMerged;

  const _CommentCard({
    required this.entry,
    required this.relativeTime,
    this.compact = false,
    this.showAvatar = true,
    this.showUserName = true,
    this.showCommentTime = true,
    this.fontScale = 1.0,
    this.spoilerIds = const {},
    this.onLongPress,
    this.onTapMerged,
  });

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  bool _revealed = false;

  bool get _isSpoiler {
    // Merged comments are spoilers if any contained comment id matches.
    if (_revealed) return false;
    for (final c in widget.entry.comments) {
      if (widget.spoilerIds.contains(c.id)) return true;
    }
    return false;
  }

  Future<void> _handleSpoilerReveal() async {
    final settings = AiSettings();
    if (!settings.spoilerWarn) {
      setState(() => _revealed = true);
      return;
    }

    var noRemind = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.spoilerWarningTitle),
          content: Text(AppLocalizations.of(context)!.spoilerWarningContent),
          actions: [
            SizedBox(
              height: 32,
              child: GestureDetector(
                onTap: () => setLocal(() => noRemind = !noRemind),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: noRemind,
                        onChanged: (v) => setLocal(() => noRemind = v ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      AppLocalizations.of(
                        context,
                      )!.chapterCommentsNoRemindAgain,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context)!.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(context)!.openButton),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (noRemind) {
      await settings.setSpoilerWarn(false);
      if (!mounted) return;
    }
    setState(() => _revealed = true);
  }

  Widget _buildSpoilerMask(
    ColorScheme cs,
    TextTheme tt, {
    required bool compact,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleSpoilerReveal,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: cs.surface.withValues(alpha: 0.62),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: compact ? 16 : 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.spoilerSuspectedComment,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final brightness = Theme.of(context).brightness;
    final entry = widget.entry;
    final compact = widget.compact;
    final showAvatar = widget.showAvatar;
    final showUserName = widget.showUserName;
    final showCommentTime = widget.showCommentTime;
    final fontScale = widget.fontScale;
    final relativeTime = widget.relativeTime;
    final horizontalPadding = compact ? 10.0 : 12.0;
    final topPadding = compact ? 8.0 : 12.0;
    final bottomPadding = compact ? 4.0 : 12.0;
    final avatarSize = compact ? 20.0 : 28.0;
    final contentSpacing = compact ? 9.0 : 8.0;
    final userStyle = _buildCommentUserStyle(tt, cs, compact: compact);
    final timeStyle = _buildCommentTimeStyle(tt, cs);
    final bodyStyle = buildCommentBodyStyle(
      tt,
      compact: compact,
      fontScale: fontScale,
    );
    final showMetaRow = showAvatar || showUserName || showCommentTime;
    final isHotMergedComment =
        entry.isMerged && _isHotMergedComment(entry.count);
    // 仅合并评论响应点击：弹出所有发表该评论的用户列表。
    final tapMerged = entry.isMerged && widget.onTapMerged != null
        ? () => widget.onTapMerged!(entry)
        : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: tapMerged,
      onLongPressStart: widget.onLongPress == null
          ? null
          : (details) => widget.onLongPress!(entry, details.globalPosition),
      onSecondaryTapDown: widget.onLongPress == null
          ? null
          : (details) => widget.onLongPress!(entry, details.globalPosition),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_commentCardCornerRadius),
        child: Stack(
          fit: compact ? StackFit.expand : StackFit.loose,
          children: [
            Container(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                topPadding,
                horizontalPadding,
                bottomPadding,
              ),
              decoration: _buildCommentCardDecoration(
                cs,
                brightness: brightness,
                highlightAsHot: isHotMergedComment,
              ),
              child: entry.isMerged
                  ? _MergedCommentContent(
                      entry: entry,
                      compact: compact,
                      contentSpacing: contentSpacing,
                      bodyStyle: bodyStyle,
                      showAvatar: showAvatar,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showMetaRow) ...[
                          Row(
                            children: [
                              if (showAvatar) ...[
                                _CommentAvatar(
                                  imageUrl: entry.primaryComment.userAvatar,
                                  size: avatarSize,
                                ),
                                SizedBox(width: compact ? 6 : 8),
                              ],
                              if (showUserName)
                                Expanded(
                                  child: Text(
                                    entry.primaryComment.userName.trim().isEmpty
                                        ? AppLocalizations.of(
                                            context,
                                          )!.commentSettingsAnonymousUser
                                        : entry.primaryComment.userName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: userStyle,
                                  ),
                                ),
                              if (showUserName && showCommentTime)
                                SizedBox(width: compact ? 6 : 8),
                              if (showCommentTime)
                                Text(relativeTime, style: timeStyle),
                            ],
                          ),
                          SizedBox(height: contentSpacing),
                        ],
                        Text(entry.content, style: bodyStyle),
                      ],
                    ),
            ),
            if (_isSpoiler)
              Positioned.fill(
                child: _buildSpoilerMask(cs, tt, compact: compact),
              ),
          ],
        ),
      ),
    );
  }
}

class _MergedCommentContent extends StatefulWidget {
  final ChapterCommentDisplayEntry entry;
  final bool compact;
  final double contentSpacing;
  final TextStyle? bodyStyle;
  final bool showAvatar;
  final Set<int> spoilerIds;

  const _MergedCommentContent({
    required this.entry,
    required this.compact,
    required this.contentSpacing,
    required this.bodyStyle,
    this.showAvatar = true,
  }) : spoilerIds = const {};

  @override
  State<_MergedCommentContent> createState() => _MergedCommentContentState();
}

class _MergedCommentContentState extends State<_MergedCommentContent> {
  bool _revealed = false;

  bool get _isSpoiler {
    if (_revealed) return false;
    for (final c in widget.entry.comments) {
      if (widget.spoilerIds.contains(c.id)) return true;
    }
    return false;
  }

  Widget _buildSpoilerOverlay(ColorScheme cs, TextTheme tt) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () async {
          final settings = AiSettings();
          if (!settings.spoilerWarn) {
            setState(() => _revealed = true);
            return;
          }
          var noRemind = false;
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => StatefulBuilder(
              builder: (ctx, setLocal) => AlertDialog(
                title: Text(AppLocalizations.of(context)!.spoilerWarningTitle),
                content: Text(
                  AppLocalizations.of(context)!.spoilerWarningContent,
                ),
                actions: [
                  SizedBox(
                    height: 32,
                    child: GestureDetector(
                      onTap: () => setLocal(() => noRemind = !noRemind),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: Checkbox(
                              value: noRemind,
                              onChanged: (v) =>
                                  setLocal(() => noRemind = v ?? false),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            AppLocalizations.of(
                              context,
                            )!.chapterCommentsNoRemindAgain,
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(AppLocalizations.of(context)!.cancelButton),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(AppLocalizations.of(context)!.openButton),
                  ),
                ],
              ),
            ),
          );
          if (ok == true) {
            if (noRemind) await settings.setSpoilerWarn(false);
            setState(() => _revealed = true);
          }
        },
        child: ClipRRect(
          borderRadius: AppRadius.xsR,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              color: cs.surface.withValues(alpha: 0.5),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: widget.compact ? 16 : 20,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppLocalizations.of(context)!.spoilerTapToView,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final entry = widget.entry;
    final compact = widget.compact;
    final showAvatar = widget.showAvatar;
    final showCountTag = _shouldShowMergedCountTag(entry.count);

    Widget spoilerWrap(Widget child) {
      if (!_isSpoiler) return child;
      return Stack(children: [child, _buildSpoilerOverlay(cs, tt)]);
    }

    if (!showAvatar) {
      if (!showCountTag) {
        return spoilerWrap(Text(entry.content, style: widget.bodyStyle));
      }
      return spoilerWrap(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(bottom: compact ? 4 : 6),
                child: _MergedCommentCountTag(
                  count: entry.count,
                  compact: compact,
                ),
              ),
            ),
            Text(entry.content, style: widget.bodyStyle),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _CommentAvatarStack(
              comments: entry.avatarComments(),
              avatarSize: compact ? 22.0 : 26.0,
              overlap: compact ? 8.0 : 10.0,
            ),
            const Spacer(),
            if (showCountTag) ...[
              const SizedBox(width: AppSpacing.sm),
              _MergedCommentCountTag(count: entry.count, compact: compact),
            ],
          ],
        ),
        SizedBox(height: widget.contentSpacing + (compact ? 1 : 2)),
        spoilerWrap(Text(entry.content, style: widget.bodyStyle)),
      ],
    );
  }
}

class _MergedCommentCountTag extends StatelessWidget {
  final int count;
  final bool compact;

  const _MergedCommentCountTag({required this.count, required this.compact});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isHot = _isHotMergedComment(count);
    final tagHeight = _mergedCountTagHeight(compact: compact);
    final minWidth = _mergedCountTagMinWidth(compact: compact, isHot: isHot);
    final horizontalPadding = _mergedCountTagHorizontalPadding(
      compact: compact,
    );
    final colors = _mergedCountTagColors(cs, isHot: isHot);
    final decoration = _buildMergedCountTagDecoration(cs, isHot: isHot);
    final label = _formatMergedCount(count);
    final iconSize = _hotCommentTagIconSize(compact: compact);

    return Container(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: tagHeight),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding / 2),
      decoration: decoration,
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isHot) ...[
              Icon(
                Icons.local_fire_department_rounded,
                size: iconSize,
                color: colors.foreground,
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              textAlign: TextAlign.center,
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
              strutStyle: const StrutStyle(height: 1, forceStrutHeight: true),
              style: tt.labelSmall?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommentAvatarStack extends StatelessWidget {
  final List<ChapterComment> comments;
  final double avatarSize;
  final double overlap;

  const _CommentAvatarStack({
    required this.comments,
    required this.avatarSize,
    required this.overlap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = comments.isEmpty
        ? const <ChapterComment>[]
        : comments.take(5).toList(growable: false);

    if (items.isEmpty) {
      return _CommentAvatar(imageUrl: '', size: avatarSize);
    }

    final width = _avatarStackWidth(
      items.length,
      avatarSize: avatarSize,
      overlap: overlap,
    );
    final inset = _avatarInset(avatarSize);

    return SizedBox(
      width: width,
      height: avatarSize,
      child: Stack(
        children: [
          for (var i = 0; i < items.length; i++)
            Positioned(
              left: i * (avatarSize - overlap),
              child: Container(
                width: avatarSize,
                height: avatarSize,
                padding: EdgeInsets.all(inset),
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                ),
                child: _CommentAvatar(
                  imageUrl: items[i].userAvatar,
                  size: avatarSize - inset * 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentAvatar extends StatelessWidget {
  final String imageUrl;
  final double size;

  const _CommentAvatar({required this.imageUrl, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: imageUrl.isEmpty
            ? ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: size * 0.5,
                  color: cs.onSurfaceVariant,
                ),
              )
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
      ),
    );
  }
}
