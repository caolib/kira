part of '../comic_detail_page.dart';

extension _ComicDetailLastBrowse on _ComicDetailPageState {
  bool get _isLastBrowseComplete {
    if (_lastBrowseTotalPage <= 0) return false;
    return _lastBrowsePage / _lastBrowseTotalPage >= 0.8;
  }

  bool get _canShowLastBrowseAction {
    if (_lastBrowseId == null) return false;
    return _usingLocalHistory || _selectedGroup == ReadingHistory.defaultGroup;
  }

  int? get _lastBrowseReaderChapterListPage {
    final recordedPage = _lastBrowseChapterListPage;
    if (recordedPage != null) return recordedPage;
    return _chapterByUuid(_lastBrowseId) != null ? _chapterPage : null;
  }

  String _continueReadingLabel() {
    final name = _truncateContinueReadingName(_lastBrowseName ?? '');
    if (_lastBrowseTotalPage > 1) {
      return name.isEmpty
          ? '$_lastBrowsePage/$_lastBrowseTotalPage'
          : '$name · $_lastBrowsePage/$_lastBrowseTotalPage';
    }
    return name;
  }

  String _truncateContinueReadingName(String name) {
    return _truncateChapterName(
      name,
      maxLength: _ComicDetailPageState._continueReadingNameMaxLength,
    );
  }

  String _truncateNextChapterName(String name) {
    return _truncateChapterName(
      name,
      maxLength: _ComicDetailPageState._nextChapterNameMaxLength,
    );
  }

  String _truncateChapterName(String name, {required int maxLength}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    final chars = trimmed.characters;
    if (chars.length <= maxLength) {
      return trimmed;
    }
    return '${chars.take(maxLength).toString()}...';
  }

  Future<void> _syncNextBrowseChapter() async {
    if (!mounted) return;

    final currentChapter = _chapterByUuid(_lastBrowseId);
    final canShowNext =
        currentChapter != null &&
        _isLastBrowseComplete &&
        currentChapter.next != null;

    if (!canShowNext) {
      if (_nextBrowseChapter != null || _nextBrowseChapterSourceId != null) {
        _setState(() {
          _nextBrowseChapter = null;
          _nextBrowseChapterListPage = null;
          _nextBrowseChapterSourceId = null;
        });
      }
      return;
    }

    final nextUuid = currentChapter.next!;
    final cachedNext = _chapterByUuid(nextUuid);
    if (cachedNext != null) {
      if (_nextBrowseChapter?.uuid != cachedNext.uuid) {
        _setState(() {
          _nextBrowseChapter = cachedNext;
          _nextBrowseChapterListPage = _chapterPage;
          _nextBrowseChapterSourceId = nextUuid;
        });
      }
      return;
    }

    if (_loadingNextBrowseChapter && _nextBrowseChapterSourceId == nextUuid) {
      return;
    }

    _loadingNextBrowseChapter = true;
    _nextBrowseChapterSourceId = nextUuid;
    try {
      final nextPage = _chapterPage < _totalPages - 1 ? _chapterPage + 1 : null;
      Chapter? nextChapter;
      if (nextPage != null) {
        final cacheKey = '$_selectedGroup:$nextPage';
        final cached = _chapterPageCache[cacheKey];
        final result =
            cached ??
            await _api.manga.getChapterList(
              widget.pathWord,
              group: _selectedGroup,
              offset: nextPage * _ComicDetailPageState._pageSize,
            );
        if (cached == null) {
          _chapterPageCache[cacheKey] = result;
        }
        for (final chapter in result.list) {
          if (chapter.uuid == nextUuid) {
            nextChapter = chapter;
            break;
          }
        }
      }

      if (nextChapter != null &&
          mounted &&
          _lastBrowseId == currentChapter.uuid) {
        _setState(() {
          _nextBrowseChapter = nextChapter;
          _nextBrowseChapterListPage = nextPage;
        });
      } else if (mounted && _lastBrowseId == currentChapter.uuid) {
        _setState(() {
          _nextBrowseChapter = null;
          _nextBrowseChapterListPage = null;
        });
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.next_browse_chapter',
        ),
      );
      if (mounted && _nextBrowseChapterSourceId == nextUuid) {
        _setState(() {
          _nextBrowseChapter = null;
          _nextBrowseChapterListPage = null;
        });
      }
    } finally {
      if (_nextBrowseChapterSourceId == nextUuid) {
        _loadingNextBrowseChapter = false;
      }
    }
  }
}
