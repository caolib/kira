part of '../novel_reader_page.dart';

extension _NovelReaderStatsPart on _NovelReaderPageState {
  bool get _canCollectReadingStats =>
      !_disposed &&
      !_loading &&
      _statsForeground &&
      (_statsRoute?.isCurrent ?? true) &&
      ReadingStats.isEnabled;

  void _initializeReadingStats() {
    if (!ReadingStats.isEnabled) return;
    _statsQueue = _statsQueue.then((_) async {
      try {
        await ReadingStats.initializeNovelsFromHistory();
      } catch (error, stack) {
        _warn(error, stack, 'stats.initialize');
      }
    });
  }

  void _onReadingStatsSettingChanged() {
    final enabled = ReadingStats.isEnabled;
    if (enabled == _statsEnabled) return;
    _statsEnabled = enabled;
    if (enabled) _initializeReadingStats();
    _refresh(() {});
  }

  void _sampleReadingStats() {
    if (!_canCollectReadingStats) return;
    if (_paged) {
      _pageViewKey.currentState?.sampleVisibleText();
    } else {
      _viewportKey.currentState?.sampleVisibleText();
    }
  }

  void _recordVisibleText(List<NovelVisibleTextRange> ranges) {
    if (!_canCollectReadingStats) return;
    final pathWord = _pathWord;
    final readAt = DateTime.now();
    // 所有身份和原文引用在同步阶段捕获，异步排队不再读取新卷/新书状态。
    final records = [
      for (final range in ranges)
        if (!range.paragraph.entry.isImage && range.end > range.start)
          (
            range: range,
            volumeId: range.paragraph.volumeId.isEmpty
                ? _volumeId
                : range.paragraph.volumeId,
            book: (_stackContents[range.paragraph.volumeId] ?? _content)
                ?.detail
                .book,
          ),
    ];
    if (records.isEmpty) return;
    final fallbackName = _fallbackName;
    // 题材属于书而非卷；分卷响应可能只携带精简书籍信息。
    var tags = widget.tags;
    if (tags.isEmpty) {
      for (final book in records.map((record) => record.book).toSet()) {
        tags = book?.themeNames ?? const [];
        if (tags.isNotEmpty) break;
      }
    }
    final localTags = tags.isEmpty
        ? (_localStatsTags ??= ref.read(localNovelTagsProvider)(pathWord))
        : null;
    _statsQueue = _statsQueue.then((_) async {
      final bookTags = localTags == null ? tags : await localTags;
      for (final record in records) {
        try {
          await ReadingStats.recordNovelReading(
            pathWord: pathWord,
            volumeId: record.volumeId,
            entryIndex: record.range.paragraph.entry.entryIndex,
            paragraphIndex: record.range.paragraph.paragraphIndex,
            text: record.range.paragraph.text,
            start: record.range.start,
            end: record.range.end,
            novelName: record.book?.name.isNotEmpty == true
                ? record.book!.name
                : fallbackName,
            tags: bookTags,
            readAt: readAt,
          );
        } catch (error, stack) {
          _warn(error, stack, 'stats.record');
        }
      }
    });
  }

  Future<void> _flushReadingStats() async {
    try {
      await _statsQueue;
      await ReadingStats.flush();
    } catch (error, stack) {
      _warn(error, stack, 'stats.flush');
    }
  }
}
