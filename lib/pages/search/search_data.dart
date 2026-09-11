part of '../search_page.dart';

extension _SearchData on _SearchPageState {

  Future<void> _doSearch(String query) async {
    final keyword = query.trim();
    if (keyword.isEmpty) return;
    final mode = _animeFeatureEnabled ? _mode : _SearchMode.comic;
    _setState(() {
      _mode = mode;
      _searching = true;
      _searchQuery = keyword;
      _comics = [];
      _animes = [];
      _offset = 0;
      _total = 0;
      _selectedTag = null;
    });

    try {
      if (mode == _SearchMode.anime) {
        final result = await _api.anime.searchAnimes(keyword);
        if (!mounted || _mode != mode || _searchQuery != keyword) return;
        _setState(() {
          _animes = result.list;
          _total = result.total;
          _offset = result.list.length;
          _searching = false;
        });
      } else {
        final result = await _api.manga.searchComics(keyword);
        if (!mounted || _mode != mode || _searchQuery != keyword) return;
        _setState(() {
          _comics = result.list;
          _total = result.total;
          _offset = result.list.length;
          _searching = false;
        });
      }
      // 搜索结果太少不可滚动时，确保搜索框/悬浮按钮不会被卡在收起态。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final c = _scrollController;
        if (!c.hasClients || c.position.pixels <= c.position.minScrollExtent) {
          _setHeaderVisible(true);
        }
      });
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_page.search',
        ),
      );
      if (mounted) _setState(() => _searching = false);
    }
  }

  Future<void> _loadComics({bool reset = true}) async {
    if (reset) {
      _setState(() {
        _mode = _SearchMode.comic;
        _offset = 0;
        _total = 0;
        _comics = [];
        _animes = [];
        _searchQuery = null;
        if (_selectedTag != null) _searching = true;
      });
    }
    try {
      final result = await _api.manga.getComicList(
        ordering: _ordering,
        offset: _offset,
        theme: _selectedTag,
      );
      if (!mounted) return;
      _setState(() {
        if (reset) {
          _comics = result.list;
        } else {
          _comics.addAll(result.list);
        }
        _total = result.total;
        _offset = _comics.length;
        _searching = false;
      });
      // 切到新结果列表后，若当前停在顶部（结果太少不可滚动的情况），
      // 主动把搜索框与悬浮按钮带回来，否则它们会卡在收起态回不来。
      if (reset) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final c = _scrollController;
          if (!c.hasClients ||
              c.position.pixels <= c.position.minScrollExtent) {
            _setHeaderVisible(true);
          }
        });
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_page.load_comics',
        ),
      );
      if (mounted) _setState(() => _searching = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _offset >= _total) return;
    _setState(() => _loadingMore = true);
    try {
      if (_searchQuery != null) {
        if (_isAnimeMode) {
          final result = await _api.anime.searchAnimes(
            _searchQuery!,
            offset: _offset,
          );
          if (!mounted) return;
          _setState(() {
            _animes.addAll(result.list);
            _offset = _animes.length;
          });
        } else {
          final result = await _api.manga.searchComics(
            _searchQuery!,
            offset: _offset,
          );
          if (!mounted) return;
          _setState(() {
            _comics.addAll(result.list);
            _offset = _comics.length;
          });
        }
      } else if (!_isAnimeMode) {
        await _loadComics(reset: false);
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'search_page.load_more',
        ),
      );
    } finally {
      if (mounted) {
        _setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }
  }
}
