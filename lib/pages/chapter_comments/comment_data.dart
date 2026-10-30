part of '../chapter_comments_sheet.dart';

extension _ChapterCommentData on _ChapterCommentsSheetState {
  Future<void> _loadComments({
    bool loadMore = false,
    bool force = false,
  }) async {
    if (!force &&
        !loadMore &&
        widget.initialComments != null &&
        _comments.isNotEmpty) {
      return;
    }
    if (loadMore) {
      if (_loading || _loadingMore) return;
      if (_comments.length >= _total) return;
      // 手动翻页优先：作废正在跑的补页循环（其 in-flight 结果会被丢弃）。
      _cancelPrefetch();
      _setState(() {
        _loadingMore = true;
        _error = null;
      });
    } else {
      // 重试首屏时取消未完成的补页，避免两路同时从 offset 0 之后追加。
      _cancelPrefetch();
      _setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final data = await _api.manga.getChapterComments(
        widget.chapterUuid,
        limit: _ChapterCommentsSheetState._pageSize,
        offset: loadMore ? _comments.length : 0,
      );
      if (!mounted) return;

      final mergedComments = loadMore
          ? appendDedupedById(_comments, data.list, (c) => c.id)
          : data.list;

      _setState(() {
        _comments = mergedComments;
        _total = data.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
      _rebuildGroupedEntries();
      _notifyCommentsUpdated();
      _maybeAutoSummary();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        tryLoadMoreWhenNearBottom();
      });
      if (!loadMore) {
        // 服务端每页只有 10 条，首屏默认补到 2 页；开启「自动加载全部」
        // 时直接走全量循环，避免两条路径同时翻页。
        if (_user.commentAutoLoadAll && _comments.length < _total) {
          unawaited(_loadAllComments());
        } else {
          unawaited(_prefetchInitialPages());
        }
      }
    } catch (e) {
      if (!mounted) return;
      _setState(() {
        _loading = false;
        _loadingMore = false;
        // 保留真实原因（DNS/TLS/超时/HTTP 状态/业务错误码），不要只留
        // 「加载失败」。
        _error = NetworkError.describe(e);
      });
    }
  }

  /// 作废正在跑的补页循环。它可能在 await 中，只能靠代数判断让它自行退出。
  void _cancelPrefetch() {
    if (!_prefetchingInitialPages) return;
    _prefetchGeneration++;
    _prefetchingInitialPages = false;
  }

  /// Refreshes page 1 after posting while keeping page 2+ data.
  ///
  /// New comments land on page 1, pushing the old page-1 tail onto page 2.
  /// When the fetched page is full, insert the old tail before existing page 2+.
  Future<void> _refreshFirstPage() async {
    // 首屏即将被替换，作废仍在跑的补页循环。
    _cancelPrefetch();
    try {
      final data = await _api.manga.getChapterComments(
        widget.chapterUuid,
        limit: _ChapterCommentsSheetState._pageSize,
      );
      if (!mounted) return;

      final firstPageComments = data.list;

      // Existing comments that belong to page 2+.
      final existingBeyondPage1 =
          _comments.length > _ChapterCommentsSheetState._pageSize
          ? _comments.sublist(_ChapterCommentsSheetState._pageSize)
          : <ChapterComment>[];

      List<ChapterComment> merged;
      if (firstPageComments.length >= _ChapterCommentsSheetState._pageSize &&
          existingBeyondPage1.isNotEmpty) {
        // A full page means the old page-1 tail overflowed to page 2.
        final overflowComment =
            _comments[_ChapterCommentsSheetState._pageSize - 1];

        // Avoid duplicating the overflow comment if it already exists.
        final allIds = <int>{
          ...firstPageComments.map((c) => c.id),
          ...existingBeyondPage1.map((c) => c.id),
        };
        final insertOverflow = !allIds.contains(overflowComment.id);

        // Remove comments duplicated by the new page 1.
        merged = appendDedupedById(
          [...firstPageComments, if (insertOverflow) overflowComment],
          existingBeyondPage1,
          (c) => c.id,
        );
      } else {
        // If page 1 is not full or page 2+ is absent, append deduped tail.
        merged = appendDedupedById(
          firstPageComments,
          existingBeyondPage1,
          (c) => c.id,
        );
      }

      _setState(() {
        _comments = merged;
        _total = data.total;
        _error = null;
      });
      _rebuildGroupedEntries();
      _notifyCommentsUpdated();
      _maybeAutoSummary();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        tryLoadMoreWhenNearBottom();
      });
      // 发表评论后首屏可能只剩一页，补齐到默认页数。
      if (!_user.commentAutoLoadAll && _comments.length < _total) {
        unawaited(_prefetchInitialPages());
      }
    } catch (e, stack) {
      if (!mounted) return;
      // Keep existing data when page-1 refresh fails; only log the issue.
      unawaited(
        AppLogger.instance.recordWarning(
          'Refresh first comment page failed: $e',
          stackTrace: stack,
          source: 'chapter_comments.refresh',
        ),
      );
    }
  }

  /// 首屏补足 [chapterCommentInitialPages] 页，页与页之间间隔
  /// [chapterCommentPageGap]。
  ///
  /// 与 `_loadAllComments` 的区别：只补到固定页数，且首屏加载态由
  /// `_loadComments` 负责，这里不再置 `_loadingMore`，避免底部先闪一下加载圈。
  Future<void> _prefetchInitialPages() async {
    final generation = _prefetchGeneration;
    bool stale() => !mounted || generation != _prefetchGeneration;
    _prefetchingInitialPages = true;
    try {
      while (!stale() && _comments.length < _total) {
        if (_comments.length >=
            _ChapterCommentsSheetState._pageSize * chapterCommentInitialPages) {
          break;
        }
        await Future<void>.delayed(chapterCommentPageGap);
        if (stale()) return;
        // 用户已手动翻页时让位，下一轮再判断是否还需要补。
        if (_loadingMore) continue;

        final offset = _comments.length;
        final data = await _api.manga.getChapterComments(
          widget.chapterUuid,
          limit: _ChapterCommentsSheetState._pageSize,
          offset: offset,
        );
        if (stale()) return;

        // 首屏期间用户可能已手动翻页，跳过重复请求结果。
        if (_comments.length != offset) continue;
        final merged = appendDedupedById(_comments, data.list, (c) => c.id);
        if (merged.length == _comments.length) break;

        _setState(() {
          _comments = merged;
          _total = data.total;
        });
        _rebuildGroupedEntries();
        _notifyCommentsUpdated();
        // 一页只有 10 条，自动总结的最小条数可能要跨页才够。
        _maybeAutoSummary();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          tryLoadMoreWhenNearBottom();
        });
      }
    } catch (e, stack) {
      // 补页失败不打断已加载内容，用户仍可手动加载更多。
      unawaited(
        AppLogger.instance.recordWarning(
          'Prefetch initial comment pages failed: $e',
          stackTrace: stack,
          source: 'chapter_comments.prefetch',
        ),
      );
    } finally {
      // 已被更新一轮补页/首屏刷新取代时，不要清掉新一轮的进行中标记。
      if (generation == _prefetchGeneration) {
        _prefetchingInitialPages = false;
      }
    }
  }

  Future<void> _loadAllComments() async {
    if (_loadingAll) return;
    _setState(() => _loadingAll = true);

    try {
      while (mounted && _comments.length < _total) {
        final data = await _api.manga.getChapterComments(
          widget.chapterUuid,
          limit: _ChapterCommentsSheetState._pageSize,
          offset: _comments.length,
        );
        if (!mounted) return;

        final newComments = data.list
            .where((item) => !_comments.any((e) => e.id == item.id))
            .toList();
        if (newComments.isEmpty) break;

        _setState(() {
          _comments = [..._comments, ...newComments];
          _total = data.total;
        });
        _rebuildGroupedEntries();
        _notifyCommentsUpdated();
        _maybeAutoSummary();

        if (_comments.length < _total) {
          await Future<void>.delayed(chapterCommentPageGap);
        }
      }
    } finally {
      if (mounted) _setState(() => _loadingAll = false);
    }
  }

  bool get _allCommentsLoaded => _total > 0 && _comments.length >= _total;
}
