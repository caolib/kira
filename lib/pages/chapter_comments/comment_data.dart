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
      if (_loading || _loadingMore || _comments.length >= _total) return;
      _setState(() => _loadingMore = true);
    } else {
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
      if (!loadMore) {
        _maybeAutoSummary();
      }
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

  /// Refreshes page 1 after posting while keeping page 2+ data.
  ///
  /// New comments land on page 1, pushing the old page-1 tail onto page 2.
  /// When the fetched page is full, insert the old tail before existing page 2+.
  Future<void> _refreshFirstPage() async {
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
    } catch (e) {
      if (!mounted) return;
      // Keep existing data when page-1 refresh fails; only log the issue.
      unawaited(
        AppLogger().recordWarning(
          'Refresh first comment page failed: $e',
          stackTrace: StackTrace.current,
        ),
      );
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

        if (_comments.length < _total) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    } finally {
      if (mounted) _setState(() => _loadingAll = false);
    }
  }

  bool get _allCommentsLoaded => _total > 0 && _comments.length >= _total;
}
