part of '../reader_page.dart';

extension _ReaderScrollMode on _ReaderPageState {
  /// 列表/翻页控件结构变化时递增版本号；重建后缩放状态一并复位。
  void _bumpScrollWidgetVersion() {
    _scrollWidgetVersion++;
    _pageImageZoomed = false;
    // 滚动模式的 PinchZoomable 不随版本号重建（控制器保持共享外置），
    // 缩放状态不会随列表重建自动复位，这里显式复位（连同惯性滑行）。
    _scrollZoomController.reset();
    // 旧列表连同其滚动活动一起被销毁，不会再派发 ScrollEndNotification；
    // 不复位「滚动中」标记的话，后续链首裁剪会被永久推迟。
    _scrollInProgress = false;
  }

  void _handlePageZoomChanged(bool zoomed) {
    if (zoomed == _pageImageZoomed) return;
    _setState(() => _pageImageZoomed = zoomed);
  }

  // ── 滚动模式 ──

  double _scrollModeTailExtent(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final extent = _isHorizontalScrollMode
        ? viewportSize.width
        : viewportSize.height;
    return extent < 280 ? 280 : extent;
  }

  /// 计算滚动模式下某章某页对应的列表 item 索引。
  /// 布局：header(可选) + 各章[图片 + 分隔(非末章)] + tail/loadMore。
  int _scrollItemIndexFor({required int chainIndex, required int page}) {
    if (_chapterScrollStarts.isEmpty) {
      _rebuildChainStructure();
    }
    if (_chapterScrollStarts.isEmpty) {
      return 0;
    }
    final chapterIndex = chainIndex.clamp(0, _chapterScrollStarts.length - 1);
    final imageCount = _chain[chapterIndex].contents.length;
    final local = (page - 1).clamp(0, imageCount > 0 ? imageCount - 1 : 0);
    return _chapterScrollStarts[chapterIndex] + local;
  }

  void _jumpToScrollPage(int page, {int? totalPages}) {
    if (!_itemScrollController.isAttached) return;
    final imageCount = totalPages ?? _detail?.contents.length ?? 0;
    if (imageCount <= 0) return;
    final clampedPage = page.clamp(1, imageCount);
    int targetIndex;
    if (_continuousReading) {
      targetIndex = _scrollItemIndexFor(
        chainIndex: _chainIndex,
        page: clampedPage,
      );
    } else {
      final hasHeader = _detail?.prev == null;
      targetIndex = (hasHeader ? 1 : 0) + (clampedPage - 1);
    }
    _itemScrollController.jumpTo(index: targetIndex);
  }

  void _onItemPositionsChanged() {
    if (!mounted || _detail == null || _isDraggingSlider) return;
    if (_isPageMode) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    if (_continuousReading) {
      _onItemPositionsChangedContinuous(positions);
      return;
    }

    final hasHeader = _detail!.prev == null;
    final imageStart = hasHeader ? 1 : 0;
    final imageCount = _detail!.contents.length;

    // 取在视口中可见面积最大的 image item 作为当前页
    int? bestImageIndex;
    double bestVisible = -1;
    for (final p in positions) {
      if (p.index < imageStart || p.index >= imageStart + imageCount) continue;
      final top = p.itemLeadingEdge.clamp(0.0, 1.0);
      final bottom = p.itemTrailingEdge.clamp(0.0, 1.0);
      final visible = bottom - top;
      if (visible > bestVisible) {
        bestVisible = visible;
        bestImageIndex = p.index - imageStart;
      }
    }

    if (bestImageIndex == null) return;
    final page = bestImageIndex + 1;
    if (page < 1 || page > imageCount) return;
    if (page == _currentPage) return;

    _setState(() => _currentPage = page);
    _saveReadingHistory();
    _preloadImages(page - 1);
  }

  /// 连续阅读滚动模式：根据 item 索引解析所属章节与章内页码，更新导航栏与历史。
  void _onItemPositionsChangedContinuous(Iterable<ItemPosition> positions) {
    if (_chapterScrollStarts.isEmpty) {
      _rebuildChainStructure();
    }
    if (_chapterScrollStarts.isEmpty) return;

    // 找到可见面积最大的图片 item（O(visible * log chapters)）。
    int? bestChapterIndex;
    int? bestLocalIndex;
    double bestVisible = -1;
    for (final p in positions) {
      final chapterIndex = _upperBoundStarts(_chapterScrollStarts, p.index);
      final start = _chapterScrollStarts[chapterIndex];
      final count = _chain[chapterIndex].contents.length;
      if (p.index < start || p.index >= start + count) continue;

      final top = p.itemLeadingEdge.clamp(0.0, 1.0);
      final bottom = p.itemTrailingEdge.clamp(0.0, 1.0);
      final visible = bottom - top;
      if (visible > bestVisible) {
        bestVisible = visible;
        bestChapterIndex = chapterIndex;
        bestLocalIndex = p.index - start;
      }
    }
    if (bestChapterIndex == null || bestLocalIndex == null) return;
    final chapterChanged = _syncActiveChapterFromGlobal(bestChapterIndex);
    final page = bestLocalIndex + 1;
    if (page == _currentPage && !chapterChanged) return;
    _currentPage = page;
    _saveReadingHistory();
    _preloadChainImages(bestChapterIndex, bestLocalIndex);
    if (chapterChanged) _preloadComments();
    // 章节切换后按「前1后1」裁剪窗口。必须排在上面的预加载之后：裁剪会前移
    // _chainIndex，预加载用的是裁剪前的索引。滚动进行中只登记待办，由
    // ScrollEndNotification 补做，不在惯性/拖动途中重建列表。
    if (chapterChanged) _pruneChainWindow();
    _setState(() {});
  }

  bool _shouldAutoAdvanceScrollChapter(ScrollNotification notification) {
    if (_detail?.next == null || _loading || _autoAdvancingChapter) {
      return false;
    }

    // tail item(下一章按钮区)是否已部分进入视口
    final hasHeader = _detail?.prev == null;
    final tailIndex = (hasHeader ? 1 : 0) + (_detail?.contents.length ?? 0);
    final positions = _itemPositionsListener.itemPositions.value;
    var tailVisible = false;
    var tailFullyVisible = false;
    for (final p in positions) {
      if (p.index != tailIndex) continue;
      tailVisible = p.itemLeadingEdge < 1.0 && p.itemTrailingEdge > 0;
      tailFullyVisible =
          p.itemLeadingEdge >= -0.05 && p.itemTrailingEdge <= 1.05;
      break;
    }
    if (!tailVisible) return false;

    if (notification is ScrollUpdateNotification) {
      // 必须 tail 已完全在视口内,且仍在向下滑,才认为是"看完最后一张图"
      if (!tailFullyVisible) return false;
      return (notification.scrollDelta ?? 0) > 0;
    }
    if (notification is OverscrollNotification) {
      return notification.overscroll > 0;
    }
    return false;
  }

  /// 滚动模式：最后一话时，"已经是最后一话"组件滚动到屏幕约 3/5 位置则返回目录。
  /// 横向滚动的末尾空白页较窄（不足视口 3/5），改为完全进入视口后仍继续
  /// 向前滑（含到头后的 overscroll）才返回目录。
  bool _shouldScrollToCatalog(ScrollNotification notification) {
    if (_scrollTailIndex < 0 || _loading || _autoAdvancingChapter) return false;

    final positions = _itemPositionsListener.itemPositions.value;
    for (final p in positions) {
      if (p.index != _scrollTailIndex) continue;
      if (_isHorizontalScrollMode) {
        final fullyVisible =
            p.itemLeadingEdge >= -0.05 && p.itemTrailingEdge <= 1.05;
        if (!fullyVisible) return false;
        if (notification is ScrollUpdateNotification) {
          return (notification.scrollDelta ?? 0) > 0;
        }
        if (notification is OverscrollNotification) {
          return notification.overscroll > 0;
        }
        return false;
      }
      // 尾部组件滚动到屏幕约 3/5 高度位置时触发跳转
      if (p.itemLeadingEdge <= 0.4) {
        return true;
      }
      break;
    }

    return false;
  }

  /// 滚动模式：已无上一话时，继续向上/向左滚动则返回详情页。
  bool _shouldScrollBackToDetail(ScrollNotification notification) {
    if (_detail == null || _loading || _autoAdvancingChapter) return false;

    final hasHeader = _detail!.prev == null;
    if (!hasHeader) return false;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return false;

    // 已无上一话：header 已完全可见且继续向上/向左滚动
    var headFullyVisible = false;
    for (final p in positions) {
      if (p.index != 0) continue;
      headFullyVisible =
          p.itemLeadingEdge >= -0.05 && p.itemTrailingEdge <= 1.05;
      break;
    }
    if (!headFullyVisible) return false;
    if (notification is ScrollUpdateNotification) {
      return (notification.scrollDelta ?? 0) < 0;
    }
    if (notification is OverscrollNotification) {
      return notification.overscroll < 0;
    }

    return false;
  }

  void _autoAdvanceToNextChapter() {
    final nextUuid = _detail?.next;
    if (nextUuid == null || _autoAdvancingChapter) return;
    _autoAdvancingChapter = true;
    _goChapter(nextUuid);
  }

  /// 放大后平移/惯性滑行期间持续喂给刹车守卫：手指仍按下时记为拖动，
  /// 抬手后的滑行记为惯性。这样惯性滑动中点击屏幕与列表惯性一样按
  /// 「刹车」处理，不会误触工具栏。
  void _onScrollZoomControllerChanged() {
    _flingBrakeGuard.recordScroll(
      isDrag: _scrollTouchFingers > 0,
      at: DateTime.now(),
    );
  }

  /// 滚动模式放大后：单指拖动时用横向分量（垂直列表）/纵向分量（横向列表）
  /// 平移视野，另一轴仍交给列表滚动。
  ///
  /// 不能走手势竞技场：列表拖动手势按总位移（含横向分量）判定，18px 即
  /// 赢下所有单指拖动，以横向为主的拖动也会被它抢走。原始指针事件与
  /// 竞技场无关，两个方向的响应可以并行（venera 同款做法）。
  void _handleScrollPointerPan(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    if (_scrollTouchFingers != 1 || !_scrollZoomController.zoomed) return;
    // 缩放识别器仍在占用手势（捏合中途抬指后的过渡态，由它继续驱动
    // 平移）：这里跳过，否则其焦点位移与下面按下的同一位移都会被应用，
    // 同一帧产生双份移动。
    if (_scrollZoomController.isScaleGestureActive) return;
    if (_scrollZoomController.isScaleGestureActive) return;
    _scrollPanGestureActive = true;
    _panVelocityTracker.addPosition(event.timeStamp, event.position);
    _scrollZoomController.pan(
      _isHorizontalScrollMode
          ? Offset(0, event.delta.dy)
          : Offset(event.delta.dx, 0),
    );
  }

  Widget _buildScrollMode() {
    final scrollDirection = _isHorizontalScrollMode
        ? Axis.horizontal
        : Axis.vertical;
    final viewportSize = MediaQuery.sizeOf(context);

    // 连续阅读：将链中各章图片依次拼接，每话末尾追加操作按钮（目录/评论）。
    // 最后一话末尾用 tail（无下一话）或 loadMore（有下一话）替换，两者自带按钮。
    // 非连续阅读：沿用原有 header + 单章图片 + tail 结构。
    // items 由 _rebuildChainStructure 缓存，避免每次 build 全量重建。
    if (_scrollItems.isEmpty && _chain.isNotEmpty) {
      _rebuildChainStructure();
    }
    final items = _scrollItems;
    final totalItems = items.length;
    // 记录尾部 item 索引，用于检测是否应返回目录
    _scrollTailIndex =
        (_continuousReading ? _chain.last.next == null : _detail!.next == null)
        ? totalItems - 1
        : -1;

    final scrollViewport = Listener(
      onPointerDown: (event) {
        _scrollTouchFingers++;
        _panVelocityTracker = VelocityTracker.withKind(PointerDeviceKind.touch);
        _scrollPanGestureActive = false;
        _scrollZoomController.stopFling();
        // 按下的瞬间列表若还在惯性滚动，这次触摸只是刹车（见 FlingBrakeTapGuard）。
        _flingBrakeGuard.onPointerDown(DateTime.now());
        _onAutoScrollTouchStart();
      },
      onPointerMove: _handleScrollPointerPan,
      onPointerUp: (event) {
        _scrollTouchFingers--;
        _onAutoScrollTouchEnd();
        // 单指拖动结束：按松手速度沿平移轴启动惯性滑行（放大状态与
        // 最小速度由控制器内部校验）。
        if (_scrollTouchFingers == 0 && _scrollPanGestureActive) {
          final velocity = _panVelocityTracker.getVelocity().pixelsPerSecond;
          _scrollZoomController.beginFling(
            _isHorizontalScrollMode
                ? Offset(0, velocity.dy)
                : Offset(velocity.dx, 0),
          );
        }
      },
      onPointerCancel: (event) {
        _scrollTouchFingers--;
        _onAutoScrollTouchEnd();
      },
      child: GestureDetector(
        onTap: _handleReadingSurfaceTap,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // 鼠标滚轮等非触摸交互通过 UserScrollNotification 暂停
            if (n is UserScrollNotification && _autoScrollEnabled) {
              _onAutoScrollWheel();
            }
            if (n is ScrollStartNotification) {
              _scrollInProgress = true;
            } else if (n is ScrollEndNotification) {
              _scrollInProgress = false;
              // 拖动/惯性结束：补做被推迟的链首裁剪。
              _flushPendingChainPrune();
            }
            if (_isDraggingSlider) return false;
            // 区分「手指仍在拖」与「抬手后的惯性」，供点击刹车判定使用。
            _recordFlingBrakeScroll(n);
            if (n is ScrollUpdateNotification &&
                _showToolbar &&
                (n.scrollDelta ?? 0).abs() > 0) {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
              _setState(() => _showToolbar = false);
            }
            if (_continuousReading) {
              _maybeAppendNextChainOnScroll();
              _maybePrependPrevChainOnScroll();
              if (_shouldScrollToCatalog(n)) {
                _autoAdvancingChapter = true;
                _exitToCatalog();
              }
            } else {
              if (_shouldAutoAdvanceScrollChapter(n)) {
                _autoAdvanceToNextChapter();
              }
              if (_shouldScrollToCatalog(n)) {
                _autoAdvancingChapter = true;
                _exitToCatalog();
              }
              if (_shouldScrollBackToDetail(n)) {
                _exitToCatalog();
              }
            }
            return false;
          },
          child: PinchZoomable(
            // 捏合缩放整个阅读视图（图片、间隙、章节分隔条一起变大），而不是
            // 单张图片。放大后的单指平移见 _handleScrollPointerPan。
            controller: _scrollZoomController,
            child: ScrollablePositionedList.separated(
              key: ValueKey(
                _continuousReading
                    ? 'scroll-continuous-$_scrollWidgetVersion'
                    : '$_currentUuid-$_scrollWidgetVersion',
              ),
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              scrollOffsetController: _scrollOffsetController,
              initialScrollIndex: _scrollModeInitialIndex,
              initialAlignment: _scrollModeInitialAlignment,
              scrollDirection: scrollDirection,
              reverse: _isReversedScrollMode,
              padding: EdgeInsets.only(top: _statusOverlayTopInset),
              physics: _isHorizontalScrollMode
                  ? null
                  : const AlwaysScrollableScrollPhysics(),
              minCacheExtent: _isHorizontalScrollMode
                  ? viewportSize.width
                  : viewportSize.height,
              itemCount: totalItems,
              separatorBuilder: (_, i) {
                final item = items[i];
                if (item.kind == ChainScrollItemKind.image) {
                  return _isHorizontalScrollMode
                      ? SizedBox(width: _user.readerImageGap)
                      : SizedBox(height: _user.readerImageGap);
                }
                return const SizedBox.shrink();
              },
              itemBuilder: (_, i) {
                final item = items[i];
                switch (item.kind) {
                  case ChainScrollItemKind.header:
                    return _FirstChapterHead(
                      isHorizontalScroll: _isHorizontalScrollMode,
                      tailExtent: _scrollModeTailExtent(context),
                    );
                  case ChainScrollItemKind.prevHead:
                    return _PrevChapterHead(
                      isHorizontalScroll: _isHorizontalScrollMode,
                      tailExtent: _scrollModeTailExtent(context),
                      isLoading: _loadingPrevChainChapter,
                    );
                  case ChainScrollItemKind.chapterDivider:
                    final chapter = item.chapter!;
                    return _ChapterDivider(
                      commentCount: _commentCountFor(chapter),
                      isHorizontalScroll: _isHorizontalScrollMode,
                      tailExtent: _scrollModeTailExtent(context),
                      onCatalog: _exitToCatalog,
                      onComments: () => _showChapterComments(chapter: chapter),
                    );
                  case ChainScrollItemKind.image:
                    final image = _buildReaderImageGesture(
                      item.chapter!,
                      item.localIndex!,
                      retryKey: item.globalIndex,
                    );
                    if (_isHorizontalScrollMode) {
                      // 横向列表会把 item 高度紧约束为视口高度，无法靠外层
                      // SizedBox 改变 item 高度。因此让图片自身以有限高度
                      // （视口高度 × scale）渲染，在视口内垂直居中、上下留白，
                      // 宽度按宽高比自适应。
                      final scale = _user.readerHorizontalImageScale;
                      return Align(
                        child: SizedBox(
                          height: viewportSize.height * scale,
                          child: image,
                        ),
                      );
                    }
                    return image;
                  case ChainScrollItemKind.tail:
                    final tailHasNext = _continuousReading
                        ? _chain.last.next != null
                        : _detail?.next != null;
                    return _NextChapterTail(
                      hasNext: tailHasNext,
                      isHorizontalScroll: _isHorizontalScrollMode,
                      tailExtent: _scrollModeTailExtent(context),
                      commentCount: _continuousReading
                          ? _commentCountFor(_chain.last)
                          : _commentCount,
                      onCatalog: _exitToCatalog,
                      onComments: _continuousReading
                          ? () => _showChapterComments(chapter: _chain.last)
                          : _showChapterComments,
                      onNextChapter: tailHasNext
                          ? () => _goChapter(
                              _continuousReading
                                  ? _chain.last.next!
                                  : _detail!.next!,
                            )
                          : null,
                    );
                  case ChainScrollItemKind.loadMore:
                    // 「加载下一话」位置与章间分隔条渲染完全一致（仅按钮行，
                    // 不显示"继续滚动"提示），追加下一话完成替换时无视觉变化，
                    // 避免条内按钮跳位。
                    return _ChapterDivider(
                      commentCount: _commentCountFor(_chain.last),
                      isHorizontalScroll: _isHorizontalScrollMode,
                      tailExtent: _scrollModeTailExtent(context),
                      onCatalog: _exitToCatalog,
                      onComments: () =>
                          _showChapterComments(chapter: _chain.last),
                    );
                }
              },
            ),
          ),
        ),
      ),
    );
    return _buildLongPressZoomSurface(scrollViewport);
  }

  /// 连续阅读滚动模式：当链尾章节最后两张图片之一进入视口且有下一话时，
  /// 提前异步追加下一话，使用户滑到底部时下一话图片已就绪，无需等待。
  void _maybeAppendNextChainOnScroll() {
    if (_loadingNextChainChapter) return;
    final lastChapter = _chain.last;
    if (lastChapter.next == null) return;
    if (lastChapter.contents.length < 2) {
      // 章节图片过少：loadMore 进入视口即触发
      final positions = _itemPositionsListener.itemPositions.value;
      for (final p in positions) {
        if (p.index >= _scrollItemCount - 1 &&
            p.itemLeadingEdge < 1.0 &&
            p.itemTrailingEdge > 0) {
          _appendNextChapterToChain();
          return;
        }
      }
      return;
    }
    // 链尾章节最后两张图片的 item 索引
    final lastImageIndex = _scrollItemIndexFor(
      chainIndex: _chain.length - 1,
      page: lastChapter.contents.length,
    );
    final triggerIndex = lastImageIndex - 1; // Second-to-last image
    final positions = _itemPositionsListener.itemPositions.value;
    for (final p in positions) {
      if ((p.index == triggerIndex || p.index == lastImageIndex) &&
          p.itemLeadingEdge < 1.0 &&
          p.itemTrailingEdge > 0) {
        _appendNextChapterToChain();
        return;
      }
    }
  }

  /// 连续阅读滚动模式：链首触发区进入视口且链首之上还有上一话时，
  /// 提前异步拼接上一话，使用户上滑到顶部时上一话图片已就绪。
  void _maybePrependPrevChainOnScroll() {
    if (_loadingPrevChainChapter) return;
    if (_chain.isEmpty || _chain.first.prev == null) return;
    final positions = _itemPositionsListener.itemPositions.value;
    for (final p in positions) {
      // 触发区恒为列表第 0 项；与链尾预取对称，进入视口即触发。
      if (p.index == 0 && p.itemLeadingEdge < 1.0 && p.itemTrailingEdge > 0) {
        _prependPrevChapterToChain();
        return;
      }
    }
  }
}
