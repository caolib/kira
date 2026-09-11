part of '../comic_detail_page.dart';

extension _ComicDetailActions on _ComicDetailPageState {
  Future<void> _toggleCollect() async {
    final comicId = _comic?.uuid;
    if (comicId == null || comicId.isEmpty) return;

    final newState = !_isCollected;
    _setState(() => _isCollected = newState);
    try {
      await _api.manga.toggleCollect(comicId, collect: newState);
      await _saveCache();
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.toggle_collect',
        ),
      );
      if (!mounted) return;
      _setState(() => _isCollected = !newState);
      await _saveCache();
    }
  }

  Future<void> _showComicComments() async {
    final comic = _comic;
    final comicId = comic?.uuid;
    if (comic == null || comicId == null || comicId.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.comicDetailCommentsUnavailable,
        isError: true,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ComicCommentsSheet(comicId: comicId, comicName: comic.name),
    );
  }

  void _openAuthorWorks(Author author) {
    final authorPathWord = author.pathWord.trim();
    if (authorPathWord.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.comicDetailAuthorUnavailable,
        isError: true,
      );
      return;
    }

    final authorName = author.name.trim().isEmpty
        ? authorPathWord
        : author.name.trim();
    context.pushNamed(
      AppRoutes.ranking,
      extra: RankingExtra(
        authorPathWord: authorPathWord,
        authorName: authorName,
      ),
    );
  }

  void _openThemeWorks(comic_model.Theme theme) {
    final themePathWord = theme.pathWord.trim();
    if (themePathWord.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.comicDetailThemeUnavailable,
        isError: true,
      );
      return;
    }

    final themeName = theme.name.trim().isEmpty
        ? themePathWord
        : theme.name.trim();
    context.pushNamed(
      AppRoutes.ranking,
      extra: RankingExtra(themePathWord: themePathWord, themeName: themeName),
    );
  }

  bool _isChapterDownloaded(String chapterUuid) =>
      _downloads.isDownloaded(widget.pathWord, chapterUuid);

  bool _isChapterQueued(String chapterUuid) =>
      _downloads.isQueued(widget.pathWord, chapterUuid);

  bool _isChapterSelectable(Chapter chapter) =>
      !_isChapterDownloaded(chapter.uuid) && !_isChapterQueued(chapter.uuid);

  void _enterSelectionMode([String? chapterUuid]) {
    _setState(() {
      _selectionMode = true;
      if (chapterUuid != null) {
        _selectedChapterIds.add(chapterUuid);
      }
    });
  }

  void _exitSelectionMode() {
    if (!_selectionMode && _selectedChapterIds.isEmpty) return;
    _setState(() {
      _selectionMode = false;
      _selectedChapterIds.clear();
    });
  }

  void _toggleDownloadSelectionMode() {
    if (_selectionMode) {
      _exitSelectionMode();
      return;
    }
    if (_displayChapters.any(_isChapterSelectable)) {
      _enterSelectionMode();
    }
  }

  void _toggleChapterSelection(Chapter chapter) {
    if (!_isChapterSelectable(chapter)) return;
    _setState(() {
      _selectionMode = true;
      if (_selectedChapterIds.contains(chapter.uuid)) {
        _selectedChapterIds.remove(chapter.uuid);
      } else {
        _selectedChapterIds.add(chapter.uuid);
      }
      if (_selectedChapterIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _selectAllVisibleDownloadable() {
    final selectableIds = _displayChapters
        .where(_isChapterSelectable)
        .map((chapter) => chapter.uuid)
        .toSet();
    // 若当前已全选则全部取消选中（但保持选中态，便于重新手动选择）。
    final allSelected =
        selectableIds.isNotEmpty &&
        selectableIds.every(_selectedChapterIds.contains);
    _setState(() {
      _selectionMode = true;
      _selectedChapterIds
        ..clear()
        ..addAll(allSelected ? const <String>{} : selectableIds);
    });
  }

  Future<void> _downloadSelectedChapters() async {
    final chapters = _displayChapters
        .where((chapter) => _selectedChapterIds.contains(chapter.uuid))
        .where(_isChapterSelectable)
        .toList();

    if (chapters.isEmpty) {
      showToast(
        context,
        AppLocalizations.of(context)!.comicDetailSelectUndownloadedChapters,
        isError: true,
      );
      return;
    }

    final added = await _downloads.enqueueChapters(
      pathWord: widget.pathWord,
      comic: _comic!,
      chapters: chapters,
      group: _selectedGroup,
    );
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;
    showToast(
      context,
      added > 0
          ? l10n.comicDetailAddedToDownloadQueue(added)
          : l10n.comicDetailSelectedAlreadyDownloadedOrQueued,
    );
    _exitSelectionMode();
  }

  Future<void> _showDownloadSettings() async {
    await showDownloadSettingsSheet(context, downloads: _downloads);
  }

  void _openReader(Chapter chapter) {
    context
        .pushNamed(
          AppRoutes.reader,
          pathParameters: {
            'pathWord': widget.pathWord,
            'chapterUuid': chapter.uuid,
          },
          extra: ReaderExtra(
            comicName: _comic?.name,
            group: _selectedGroup,
            chapterName: chapter.name,
            chapterListPage: _chapterPage,
          ),
        )
        .then((_) => _loadLocalHistory());
  }

  /// 通过系统分享面板分享漫画的 https 落地页链接（见 [KiraLinks.comicShareUrl]），
  /// 接收方点击后由系统或落地页拉起 kira 并打开本漫画详情页。
  Future<void> _shareComic() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _comic?.name ?? widget.pathWord;
    // 分享面板关闭时 app 恢复前台会触发剪贴板检测；先把自己分享的链接
    // 记为已处理，避免分享者收到自己刚分享的提示。
    unawaited(SharedLinkRecord.markHandled(widget.pathWord));
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: l10n.comicDetailShareContent(
            name,
            KiraLinks.comicShareUrl(widget.pathWord),
          ),
          subject: name,
        ),
      );
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'comic_detail.share',
        ),
      );
    }
  }
}
