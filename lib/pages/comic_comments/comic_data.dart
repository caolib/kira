part of '../comic_comments_sheet.dart';

extension _ComicData on _ComicCommentsSheetState {
  Future<void> _loadComments({bool loadMore = false}) async {
    if (loadMore) {
      if (_loading || _loadingMore || _comments.length >= _total) return;
      _setState(() => _loadingMore = true);
    } else {
      _setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _api.manga.getComicComments(
        widget.comicId,
        offset: loadMore ? _comments.length : 0,
      );
      if (!mounted) return;

      final deduped = loadMore
          ? appendDedupedById(_comments, data.list, (c) => c.id)
          : data.list;

      _setState(() {
        _comments = deduped;
        _total = data.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      _rebuildGroupedEntries();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        tryLoadMoreWhenNearBottom();
      });
    } catch (e) {
      if (!mounted) return;
      _setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  /// Rebuilds the grouped comment cache after _comments changes.
  void _rebuildGroupedEntries() {
    if (_comments.isEmpty) {
      _groupedEntries = const [];
      _blockedCount = 0;
      return;
    }
    final blockwords = _user.commentBlockwords;
    final hasBlockwords = blockwords.isNotEmpty || _user.commentBlockGroupSpam;
    final blocked = _user.commentBlockedUsers;
    if (blocked.isEmpty && !hasBlockwords) {
      _groupedEntries = groupComicComments(_comments);
      _blockedCount = 0;
      return;
    }
    final filtered = _comments
        .where(
          (c) =>
              !_user.isCommentUserBlocked(c.userId, c.userName.trim()) &&
              !_user.isCommentBlockedByWord(c.comment) &&
              !_user.isCommentGroupSpam(c.comment),
        )
        .toList();
    _blockedCount = _comments.length - filtered.length;
    _groupedEntries = groupComicComments(filtered);
  }

  Future<void> _toggleReplies(ComicComment comment) async {
    final currentState = _replyStateOf(comment.id);
    if (currentState.expanded) {
      _setState(() {
        _replyStates[comment.id] = currentState.copyWith(
          expanded: false,
          error: null,
        );
      });
      return;
    }

    _setState(() {
      _replyStates[comment.id] = currentState.copyWith(
        expanded: true,
        error: null,
      );
    });

    if (currentState.replies.isEmpty && !currentState.loading) {
      await _loadReplies(comment);
    }
  }

  Future<void> _loadReplies(
    ComicComment comment, {
    bool loadMore = false,
  }) async {
    final currentState = _replyStateOf(comment.id);
    final knownTotal = currentState.total > 0
        ? currentState.total
        : comment.replyCount;

    if (loadMore) {
      if (currentState.loading || currentState.loadingMore) return;
      if (currentState.replies.length >= knownTotal) return;
    } else if (currentState.loading) {
      return;
    }

    _setState(() {
      _replyStates[comment.id] = currentState.copyWith(
        expanded: true,
        loading: !loadMore,
        loadingMore: loadMore,
        error: null,
      );
    });

    try {
      final data = await _api.manga.getComicComments(
        widget.comicId,
        replyId: comment.id.toString(),
        limit: _ComicCommentsSheetState._replyPageSize,
        offset: loadMore ? currentState.replies.length : 0,
      );
      if (!mounted) return;

      final mergedReplies =
          (loadMore
                  ? [
                      ...currentState.replies,
                      ...data.list.where(
                        (item) => !currentState.replies.any(
                          (existing) => existing.id == item.id,
                        ),
                      ),
                    ]
                  : data.list)
              .where(
                (item) =>
                    !_user.isCommentUserBlocked(
                      item.userId,
                      item.userName.trim(),
                    ) &&
                    !_user.isCommentBlockedByWord(item.comment) &&
                    !_user.isCommentGroupSpam(item.comment),
              )
              .toList();

      // 回复按时间正序（从旧到新）
      mergedReplies.sort((a, b) => a.createAt.compareTo(b.createAt));

      final latestState = _replyStateOf(comment.id);

      _setState(() {
        _replyStates[comment.id] = latestState.copyWith(
          loading: false,
          loadingMore: false,
          replies: mergedReplies,
          total: data.total,
          error: null,
        );
      });
    } catch (e) {
      if (!mounted) return;
      final latestState = _replyStateOf(comment.id);
      _setState(() {
        _replyStates[comment.id] = latestState.copyWith(
          loading: false,
          loadingMore: false,
          error: e.toString(),
        );
      });
    }
  }

  void _applyBlockedFilter() {
    _setState(() {
      _comments = _comments
          .where(
            (c) =>
                !_user.isCommentUserBlocked(c.userId, c.userName.trim()) &&
                !_user.isCommentBlockedByWord(c.comment) &&
                !_user.isCommentGroupSpam(c.comment),
          )
          .toList();
      // 已展开的回复也需过滤
      for (final id in _replyStates.keys.toList()) {
        final s = _replyStates[id]!;
        if (s.replies.isEmpty) continue;
        final filtered = s.replies
            .where(
              (r) =>
                  !_user.isCommentUserBlocked(r.userId, r.userName.trim()) &&
                  !_user.isCommentBlockedByWord(r.comment) &&
                  !_user.isCommentGroupSpam(r.comment),
            )
            .toList();
        if (filtered.length != s.replies.length) {
          _replyStates[id] = s.copyWith(replies: filtered);
        }
      }
    });
    _rebuildGroupedEntries();
  }
}
