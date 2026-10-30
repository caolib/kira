part of '../novel_reader_page.dart';

/// 滚动模式的连续阅读：卷尾继续下滑无缝追加下一卷，卷首继续回滑拼接
/// 上一卷。
///
/// 只保留「当前卷 + 相邻一卷」两卷正文。翻页模式、目录跳卷、工具栏上/下一卷
/// 仍是整卷替换（[_NovelReaderPageState._loadVolume]），不走这里。
extension _NovelReaderContinuousPart on _NovelReaderPageState {
  /// 与 [NovelReaderPage._adjacentVolume] 同一套判定，但以任意卷为起点：
  /// 优先卷自身的前后链接，回退到卷列表顺序。
  String? _adjacentVolumeOf(String volumeId, int direction) {
    final volume = _volumeDetails[volumeId]?.volume;
    final linked = direction < 0 ? volume?.prev : volume?.next;
    if (linked != null && linked.isNotEmpty && linked != volumeId) {
      return linked;
    }
    final index = _volumes.indexWhere((item) => item.id == volumeId);
    final next = index + direction;
    return index >= 0 && next >= 0 && next < _volumes.length
        ? _volumes[next].id
        : null;
  }

  /// 卷栈末尾之后的下一卷；栈为空时从当前卷算起。
  String? get _nextStackVolumeId => _adjacentVolumeOf(
    _stackVolumes.isEmpty ? _volumeId : _stackVolumes.last.volumeId,
    1,
  );

  /// 卷栈起始之前的上一卷；栈为空时从当前卷算起。
  String? get _previousStackVolumeId => _adjacentVolumeOf(
    _stackVolumes.isEmpty ? _volumeId : _stackVolumes.first.volumeId,
    -1,
  );

  /// 加载一卷正文供追加，同一卷的并发请求共享一次网络往返。
  /// 若该卷已有只读缓存的预取结果，先尝试复用；预取失败再走正常加载。
  /// [refresh] 用于显式重试：跳过预取与缓存，重新向来源请求。
  Future<NovelVolumeContent> _stackContent(
    String volumeId, {
    bool refresh = false,
  }) {
    final pending = _stackLoads[volumeId];
    if (pending != null) return pending;
    final loading = _resolveStackContent(volumeId, refresh: refresh);
    _stackLoads[volumeId] = loading;
    // 失败后允许下一次预取/追加重试，不能把失败 Future 永久缓存。
    // 这里同时消费掉错误，避免派生的 Future 变成未处理异常。
    unawaited(
      loading.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          // 期间可能已被重新发起：只清理自己这一份。
          if (identical(_stackLoads[volumeId], loading)) {
            _stackLoads.remove(volumeId);
          }
        },
      ),
    );
    return loading;
  }

  Future<NovelVolumeContent> _resolveStackContent(
    String volumeId, {
    bool refresh = false,
  }) async {
    if (!refresh) {
      final prefetched = _stackPrefetches.remove(volumeId);
      if (prefetched != null) {
        try {
          return await prefetched;
        } on Object {
          // 预取只读缓存，没有缓存是常态：回退到正常加载。
        }
      }
    }
    final content = await _source.loadContent(
      _pathWord,
      volumeId,
      refresh: refresh,
    );
    return _validateStackContent(content);
  }

  /// 只读缓存预取：不联网，也不会把尚未进入的卷写进服务端浏览记录。
  Future<NovelVolumeContent> _prefetchStackContent(String volumeId) {
    final pending = _stackPrefetches[volumeId];
    if (pending != null) return pending;
    final loading = _source
        .loadContent(_pathWord, volumeId, cachedOnly: true)
        .then(_validateStackContent);
    _stackPrefetches[volumeId] = loading;
    unawaited(
      loading.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_stackPrefetches[volumeId], loading)) {
            _stackPrefetches.remove(volumeId);
          }
        },
      ),
    );
    return loading;
  }

  NovelVolumeContent _validateStackContent(NovelVolumeContent? content) {
    if (content == null) throw const _NoCachedVolume();
    if (content.detail.isLocked) throw NovelAccessException(content.detail);
    return content;
  }

  /// 卷栈变化后淘汰窗口外的预取结果，避免来回滑动累积整卷正文。
  /// 保留两卷本身以及两侧各一个相邻预取目标。
  void _pruneStackLoads() {
    if (_stackVolumes.isEmpty) {
      _stackLoads.clear();
      _stackPrefetches.clear();
      return;
    }
    final keep = <String>{for (final volume in _stackVolumes) volume.volumeId};
    final previous = _previousStackVolumeId;
    if (previous != null) keep.add(previous);
    final next = _nextStackVolumeId;
    if (next != null) keep.add(next);
    _stackLoads.removeWhere((volumeId, _) => !keep.contains(volumeId));
    _stackPrefetches.removeWhere((volumeId, _) => !keep.contains(volumeId));
  }

  /// 进入卷末约两屏时预取下一卷，触发点到来时内容已就绪。
  void _prefetchNextVolume() {
    if (_paged || _loading || _disposed) return;
    final next = _nextStackVolumeId;
    if (next == null || _stackLoads.containsKey(next)) return;
    unawaited(
      _stackContent(next).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          // 预取失败不打扰读者：滚动到接缝时才显示错误与重试。
          _warn(error, stack, 'continuous.prefetch');
        },
      ),
    );
  }

  /// 卷末最后一行上移，距视口底部超过 10% 屏高：把下一卷正文接到当前卷之后。
  Future<void> _appendNextVolume({bool force = false}) async {
    if (_paged || _loading || _disposed) return;
    if (_appending || _prepending) {
      // 反方向拼接占用了卷栈：本次触发作废，但要让视口还能再次触发。
      _viewportKey.currentState?.rearmSeams();
      return;
    }
    final next = _nextStackVolumeId;
    if (next == null) return;
    if (!force && _seamError != null) return;
    final session = _session;
    final request = _request;
    _refresh(() {
      _appending = true;
      _seamError = null;
      _seamUnavailable = false;
    });
    try {
      final content = await _stackContent(next, refresh: force);
      if (!_active(session) || request != _request) return;
      final volume = NovelReaderVolumeDocument(
        volumeId: next,
        volumeName: content.detail.volume.name,
        document: NovelReaderDocument(
          content.entries,
          ignoreBlankParagraphs: _settings.ignoreBlankParagraphs,
        ),
      );
      if (volume.document.itemCount == 0) {
        // 空卷不是有效结果：清掉缓存，显式重试才能重新请求。
        unawaited(_stackLoads.remove(next));
        _refresh(() {
          _appending = false;
          _seamError = const _NoCachedVolume();
        });
        return;
      }
      final location = _viewerLocation ?? _location;
      // 请求期间读者可能已回滑：回收对象必须在应用结果时重新判断。
      final readingVolume = _currentVolumeId;
      var aborted = false;
      _refresh(() {
        _appending = false;
        // 读者已回到将被回收的首卷：放弃追加，内容留在预取里下次再用。
        if (_stackVolumes.length > 1 &&
            _stackVolumes.first.volumeId == readingVolume) {
          aborted = true;
          return;
        }
        _stackContents[next] = content;
        _volumeDetails[next] = content.detail;
        _stackVolumes.add(volume);
        // 当前卷跟着读者走：工具栏、书签、目录与重试都以它为准。
        _volumeId = readingVolume;
        // 只保留当前卷 + 下一卷：追加第三卷时，读者已在第二卷里，回收第一卷。
        final recycled = _stackVolumes.length > 2;
        if (recycled) {
          final dropped = _stackVolumes.removeAt(0);
          _stackContents.remove(dropped.volumeId);
          _stackLoads.remove(dropped.volumeId);
          // 卷首提示指向的是已不在栈里的更早一卷，不能留到新的卷首。
          _headSeamError = null;
          _headSeamUnavailable = false;
        }
        _stack = NovelReaderStack(List.of(_stackVolumes));
        _document = _stack;
        ++_contentRevision;
        if (location != null) {
          // 回收改变了 item 下标：按当前位置重定位，视口不会跳。
          _target = _document!.anchorFor(
            _document!.itemFor(location.anchor),
            alignment: location.anchor.alignment,
          );
          if (recycled) ++_jumpRevision;
        }
        _pruneStackLoads();
      });
      if (aborted) _viewportKey.currentState?.rearmSeams();
    } catch (error, stack) {
      _warn(error, stack, 'continuous.append');
      if (!_active(session) || request != _request) return;
      _refresh(() {
        _appending = false;
        _seamError = error;
        _seamUnavailable = error is NovelDownloadUnavailableException;
      });
    }
  }

  /// 进入卷首约一屏时尝试预取上一卷，回滑到顶时内容已就绪。
  /// 只读正文缓存：回翻多数时候是重读已缓存的卷，既不联网，也不会把
  /// 尚未进入的卷写进服务端浏览记录。
  void _prefetchPreviousVolume() {
    if (_paged || _loading || _disposed) return;
    final previous = _previousStackVolumeId;
    if (previous == null ||
        _stackLoads.containsKey(previous) ||
        _stackPrefetches.containsKey(previous)) {
      return;
    }
    unawaited(
      _prefetchStackContent(previous).then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          // 没有缓存是常态，回滑到卷首时再正常加载；其余失败同样不打扰。
          if (error is _NoCachedVolume) return;
          _warn(error, stack, 'continuous.prefetchPrevious');
        },
      ),
    );
  }

  /// 卷首第一段回到视口内、读者仍在回滑：把上一卷接到当前卷之前。
  Future<void> _prependPreviousVolume({bool force = false}) async {
    if (_paged || _loading || _disposed) return;
    if (_prepending || _appending) {
      // 反方向拼接占用了卷栈：本次触发作废，但要让视口还能再次触发。
      _viewportKey.currentState?.rearmSeams();
      return;
    }
    final previous = _previousStackVolumeId;
    if (previous == null) return;
    if (!force && _headSeamError != null) return;
    final session = _session;
    final request = _request;
    _refresh(() {
      _prepending = true;
      _headSeamError = null;
      _headSeamUnavailable = false;
    });
    try {
      final content = await _stackContent(previous, refresh: force);
      if (!_active(session) || request != _request) return;
      final volume = NovelReaderVolumeDocument(
        volumeId: previous,
        volumeName: content.detail.volume.name,
        document: NovelReaderDocument(
          content.entries,
          ignoreBlankParagraphs: _settings.ignoreBlankParagraphs,
        ),
      );
      if (volume.document.itemCount == 0) {
        // 空卷不是有效结果：清掉缓存，显式重试才能重新请求。
        unawaited(_stackLoads.remove(previous));
        _refresh(() {
          _prepending = false;
          _headSeamError = const _NoCachedVolume();
        });
        return;
      }
      final location = _viewerLocation ?? _location;
      // 请求期间读者可能已滑进栈尾：回收对象必须在应用结果时重新判断。
      final readingVolume = _currentVolumeId;
      var aborted = false;
      _refresh(() {
        _prepending = false;
        // 读者已进入将被回收的尾卷：放弃前插，内容留在预取里下次再用。
        if (_stackVolumes.length > 1 &&
            _stackVolumes.last.volumeId == readingVolume) {
          aborted = true;
          return;
        }
        _stackContents[previous] = content;
        _volumeDetails[previous] = content.detail;
        _stackVolumes.insert(0, volume);
        // 阅读卷不因前插而改变；回收发生时它一定还在栈里。
        _volumeId = readingVolume;
        // 仍只保留两卷：卷首拼接时回收栈尾（读者此刻在卷首，栈尾离得最远）。
        if (_stackVolumes.length > 2) {
          final dropped = _stackVolumes.removeLast();
          _stackContents.remove(dropped.volumeId);
          _stackLoads.remove(dropped.volumeId);
          // 卷尾提示指向的是已不在栈里的更后一卷，不能留到新的卷尾。
          _seamError = null;
          _seamUnavailable = false;
        }
        _stack = NovelReaderStack(List.of(_stackVolumes));
        _document = _stack;
        ++_contentRevision;
        if (location != null) {
          // 卷首插入使所有已有下标后移：按当前位置重定位，视口不会跳。
          _target = _document!.anchorFor(
            _document!.itemFor(location.anchor),
            alignment: location.anchor.alignment,
          );
        }
        ++_jumpRevision;
        _pruneStackLoads();
      });
      if (aborted) _viewportKey.currentState?.rearmSeams();
    } catch (error, stack) {
      _warn(error, stack, 'continuous.prepend');
      if (!_active(session) || request != _request) return;
      _refresh(() {
        _prepending = false;
        _headSeamError = error;
        _headSeamUnavailable = error is NovelDownloadUnavailableException;
      });
    }
  }

  /// 卷首接缝处的内联提示：上一卷加载失败 / 本地未下载。
  Widget? _buildHeadSeam() {
    final error = _headSeamError;
    if (error == null || _paged) return null;
    final l10n = AppLocalizations.of(context)!;
    final palette = NovelReaderPalette.resolve(
      _settings,
      MediaQuery.platformBrightnessOf(context),
    );
    final message = _headSeamUnavailable
        ? l10n.novelDownloadUnavailable
        : novelErrorMessage(error, fallback: l10n.novelReaderLoadFailed);
    return Padding(
      key: const ValueKey('novel-reader-head-seam'),
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.meta(
              Theme.of(context).textTheme,
            )?.copyWith(color: palette.foreground.withValues(alpha: 0.7)),
          ),
          if (!_headSeamUnavailable)
            TextButton(
              key: const ValueKey('novel-reader-head-seam-retry'),
              onPressed: _prepending
                  ? null
                  : () => unawaited(_prependPreviousVolume(force: true)),
              child: Text(l10n.retryButton),
            ),
        ],
      ),
    );
  }

  /// 接缝处的内联提示：只在加载失败 / 本地未下载时出现，正常加载保持
  /// 无缝（读者看到的是卷末最后一段与空白）。
  Widget? _buildSeam() {
    final error = _seamError;
    if (error == null || _paged) return null;
    final l10n = AppLocalizations.of(context)!;
    final palette = NovelReaderPalette.resolve(
      _settings,
      MediaQuery.platformBrightnessOf(context),
    );
    final message = _seamUnavailable
        ? l10n.novelDownloadUnavailable
        : novelErrorMessage(error, fallback: l10n.novelReaderLoadFailed);
    return Padding(
      key: const ValueKey('novel-reader-seam'),
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.meta(
              Theme.of(context).textTheme,
            )?.copyWith(color: palette.foreground.withValues(alpha: 0.7)),
          ),
          if (!_seamUnavailable)
            TextButton(
              key: const ValueKey('novel-reader-seam-retry'),
              onPressed: _appending
                  ? null
                  : () => unawaited(_appendNextVolume(force: true)),
              child: Text(l10n.retryButton),
            ),
        ],
      ),
    );
  }
}
