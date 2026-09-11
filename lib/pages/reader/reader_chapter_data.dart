part of '../reader_page.dart';

extension _ReaderChapterData on _ReaderPageState {
  Future<dynamic> _handleVolumeMethod(MethodCall call) async {
    if (!_user.readerVolumeKey || !_isPageMode || _detail == null) return;
    if (call.method == 'volumeUp') _prevPage();
    if (call.method == 'volumeDown') _nextPage();
  }

  void _updateVolumeIntercept() {
    final should = _isPageMode && _user.readerVolumeKey;
    _setVolumeIntercept(should);
  }

  /// 设置变化时重建，并重新套用依赖设置的副作用（音量键拦截）。
  void _onUserSettingsChanged() {
    if (!mounted) return;
    _setState(() {});
    _updateVolumeIntercept();
  }

  Future<void> _setVolumeIntercept(bool enabled) async {
    if (!_volumeChannelAvailable) return;
    try {
      await _ReaderPageState._volumeChannel.invokeMethod(
        enabled ? 'enable' : 'disable',
      );
    } on MissingPluginException {
      _volumeChannelAvailable = false;
    } on PlatformException catch (e) {
      debugPrint('Volume channel unavailable: $e');
      _volumeChannelAvailable = false;
    }
  }

  Future<void> _loadChapter({bool forceRefresh = false}) async {
    if (forceRefresh && _refreshingChapter) return;
    final previousPage = _currentPage;
    _setState(() {
      if (forceRefresh) {
        _refreshingChapter = true;
      } else {
        _loading = true;
        _loadError = null;
      }
      _scrollTailIndex = -1;
    });
    try {
      final detail =
          (forceRefresh
              ? null
              : await _downloads.getDownloadedChapterDetail(
                  widget.pathWord,
                  _currentUuid,
                )) ??
          await _api.manga.getChapterDetail(
            widget.pathWord,
            _currentUuid,
            forceRefresh: forceRefresh,
          );
      if (detail.contents.isEmpty) {
        throw StateError('Chapter has no readable pages');
      }
      if (!mounted) return;
      // 首次加载且有 initialPage 参数时跳到指定页
      final startPage = forceRefresh
          ? previousPage.clamp(1, detail.contents.length)
          : (_isFirstLoad && widget.initialPage > 1
                ? widget.initialPage.clamp(1, detail.contents.length)
                : 1);
      _isFirstLoad = false;
      _setState(() {
        _detail = detail;
        _loading = false;
        _loadError = null;
        _refreshingChapter = false;
        _currentPage = startPage;
        _imageReloadVersions.clear();
        _imageRetryCounts.clear();
        _imageRetryTokens.clear();
        _imageNaturalSizes.clear();
        // 重置连续阅读链：首项即当前章节。
        _chain
          ..clear()
          ..add(detail);
        _chainIndex = 0;
        _loadingNextChainChapter = false;
        _loadingPrevChainChapter = false;
        _rebuildChainStructure();
        // 整章切换：重建图片归属注册表（供阅读统计埋点反查）
        _registerChapterStatsUrls(detail, clearFirst: true);
        _scrollModeInitialIndex = _scrollItemIndexFor(
          chainIndex: 0,
          page: startPage,
        );
        _scrollModeInitialAlignment = 0.0;
        _bumpScrollWidgetVersion();
      });
      if (_isPageMode) {
        final oldController = _pageController;
        final initialIndex = _chainChapterStart(_chainIndex) + (startPage - 1);
        _pageController = PageController(initialPage: initialIndex);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          oldController.dispose();
        });
      }
      _autoAdvancingChapter = false;
      _saveReadingHistory();
      unawaited(_preloadComments());
      // 提前读取漫画名/标签，让图片加载统计埋点能尽早拿到完整 meta。
      unawaited(_comicMetaFromCache());
      // If cache has no next chapter, refresh navigation silently in background.
      if (!forceRefresh && !detail.isDownloaded && detail.next == null) {
        _refreshChapterMetadata(detail);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _preloadImages(startPage - 1);
        // Chapter switches interrupt auto-scroll; resume after rebuild if enabled.
        // Wait for first images to load before resuming to avoid scrolling blanks.
        if (_autoScrollEnabled && !_isPageMode) {
          final gen = ++_autoScrollGeneration;
          Future.delayed(const Duration(seconds: 3), () {
            if (gen != _autoScrollGeneration) return;
            if (mounted && _autoScrollEnabled && !_isPageMode) {
              _continueAutoScroll();
            }
          });
        }
      });
      if (forceRefresh && mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.readerImageLinksRefreshed,
        );
      }
    } catch (e) {
      _autoAdvancingChapter = false;
      if (mounted) {
        final message = NetworkError.message(
          e,
          l10n: AppLocalizations.of(context)!,
        );
        _setState(() {
          if (!forceRefresh || _detail == null) {
            _loading = false;
            _loadError = message;
          }
          if (forceRefresh) _refreshingChapter = false;
        });
        if (forceRefresh) {
          showToast(
            context,
            AppLocalizations.of(context)!.refreshFailedWithError(message),
            isError: true,
          );
        }
      }
    }
  }

  Future<void> _refreshChapter() async {
    final detail = _detail;
    if (_loading || _refreshingChapter || detail == null) return;
    if (detail.isDownloaded) {
      showToast(
        context,
        AppLocalizations.of(context)!.readerLocalChapterNoRefresh,
      );
      return;
    }
    await _loadChapter(forceRefresh: true);
  }

  /// Refreshes cached chapter navigation fields (next/prev) silently.
  /// Only updates UI/cache when navigation changes.
  void _refreshChapterMetadata(ChapterDetail cached) {
    final chapterUuid = cached.uuid;
    _api.manga
        .getChapterDetail(widget.pathWord, chapterUuid, forceRefresh: true)
        .then((fresh) {
          if (!mounted || _currentUuid != chapterUuid || _detail == null) {
            return;
          }
          // Update only when navigation changes; content changes require manual refresh.
          if (fresh.next == cached.next && fresh.prev == cached.prev) {
            return;
          }
          _setState(() {
            final updated = _detail!.copyWith(
              next: fresh.next,
              prev: fresh.prev,
            );
            _detail = updated;
            // Sync chain so continuous reading uses latest navigation.
            if (_chainIndex < _chain.length) {
              _chain[_chainIndex] = updated;
            }
            _rebuildChainStructure();
          });
        })
        .catchError((Object _) {
          // Background refresh failures do not affect reading.
        });
  }

  void _onBookmarksChanged() {
    if (mounted) _setState(() {});
  }

  Future<void> _toggleBookmark() async {
    final detail = _detail;
    if (detail == null) return;
    final l10n = AppLocalizations.of(context)!;
    // 快照点击时的阅读位置，避免等待期间翻页导致书签记错位置。
    final chapterUuid = _currentUuid;
    final chapterName = detail.name.isNotEmpty
        ? detail.name
        : widget.chapterName;
    final page = _currentPage;
    final meta = await _comicMetaFromCache();
    if (!mounted) return;
    final added = await _bookmarks.toggle(
      pathWord: widget.pathWord,
      comicName: widget.comicName?.isNotEmpty == true
          ? widget.comicName!
          : meta.comicName,
      cover: meta.cover,
      group: meta.group,
      chapterUuid: chapterUuid,
      chapterName: chapterName,
      page: page,
    );
    if (!mounted) return;
    showToast(context, added ? l10n.bookmarkAdded : l10n.bookmarkRemoved);
  }

  /// 从漫画详情本地缓存读取漫画名、封面、标签与分组（纯缓存读取，无网络请求）。
  /// 分组缺失时回退到 widget.group（详情页入口会传入当前选中分组）。
  /// 顺带填充 [_statsComicMetaByPath]，供图片加载统计埋点复用。
  Future<({String comicName, String cover, String group, List<String> tags})>
  _comicMetaFromCache() async {
    final fallbackGroup = widget.group?.trim() ?? '';
    try {
      final data = await ComicDetailRepository(widget.pathWord).loadFromCache();
      final comic = data?.comic;
      final cachedGroup = data?.selectedGroup.trim() ?? '';
      if (cachedGroup.isNotEmpty) _cachedSelectedGroup = cachedGroup;
      final name = comic?.name ?? '';
      // 显式类别避免 ?. 链推断为 List<dynamic>
      var tags = const <String>[];
      if (comic != null) {
        tags = comic.themes
            .where((t) => t.name.isNotEmpty)
            .map((t) => t.name)
            .toList(growable: false);
      }
      // 懒填充缓存：供图片加载统计埋点复用，避免埋点时再次读盘
      if (comic != null) {
        _statsComicMetaByPath[widget.pathWord] = (name: name, tags: tags);
      }
      return (
        comicName: name,
        cover: comic?.cover ?? '',
        group: cachedGroup.isNotEmpty ? cachedGroup : fallbackGroup,
        tags: tags,
      );
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'reader.comic_meta_from_cache',
        ),
      );
      return (
        comicName: '',
        cover: '',
        group: fallbackGroup,
        tags: const <String>[],
      );
    }
  }

  void _saveReadingHistory() {
    // 书签等入口不传 group：回退到详情缓存中的选中分组，
    // 否则历史会写入默认键，详情页按分组读取时看不到更新。
    var group = widget.group;
    if (group == null || group.trim().isEmpty) {
      group = _cachedSelectedGroup ?? ReadingHistory.defaultGroup;
    }
    ReadingHistory.save(
      pathWord: widget.pathWord,
      group: group,
      chapterUuid: _currentUuid,
      chapterName: _detail?.name ?? widget.chapterName,
      chapterListPage: widget.chapterListPage,
      page: _currentPage,
      totalPage: _detail?.contents.length ?? 0,
    );
  }

  /// 登记某章图片 URL → 归属，供图片加载统计埋点反查。
  /// 命中磁盘缓存的图片不会进入请求层，天然不计入；本地已下载章节
  /// （以文件方式渲染）也不会触发网络请求，一并跳过登记。
  /// [clearFirst] 为 true 时先清空再登记（整章切换重建注册表，长度有界）。
  void _registerChapterStatsUrls(
    ChapterDetail chapter, {
    bool clearFirst = false,
  }) {
    if (chapter.isDownloaded) return;
    if (clearFirst) _statsImageOwnerByUrl.clear();
    final pathWord = widget.pathWord;
    for (final url in chapter.contents) {
      if (url.isEmpty) continue;
      _statsImageOwnerByUrl[url] = (
        pathWord: pathWord,
        chapterUuid: chapter.uuid,
      );
    }
  }

  Future<void> _loadCachedSelectedGroup() async {
    if (_cachedSelectedGroup != null) return;
    try {
      final data = await ComicDetailRepository(widget.pathWord).loadFromCache();
      final group = data?.selectedGroup.trim() ?? '';
      if (group.isNotEmpty) _cachedSelectedGroup = group;
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'reader.load_cached_selected_group',
        ),
      );
    }
  }
}
