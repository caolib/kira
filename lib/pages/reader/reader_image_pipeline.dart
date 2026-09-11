part of '../reader_page.dart';

extension _ReaderImagePipeline on _ReaderPageState {
  CacheManager get _readerImageCacheManager {
    final seconds = _user.imageLoadTimeout;
    if (_ReaderPageState._cachedImageManager == null ||
        _ReaderPageState._cachedImageManagerTimeout != seconds) {
      _ReaderPageState._cachedImageManager = CacheManager(
        Config(
          'readerImageCache',
          fileService: _ReaderImageFileService(Duration(seconds: seconds)),
        ),
      );
      _ReaderPageState._cachedImageManagerTimeout = seconds;
    }
    return _ReaderPageState._cachedImageManager!;
  }

  // ── 图片预加载 ──

  void _preloadImages(int centerIndex, {int range = 2}) {
    if (_detail == null || _detail!.isDownloaded) return;
    final count = _detail!.contents.length;
    for (int offset = -range; offset <= range; offset++) {
      final i = centerIndex + offset;
      if (i < 0 || i >= count) continue;
      precacheImage(
        CachedNetworkImageProvider(
          _detail!.contents[i],
          cacheManager: _readerImageCacheManager,
        ),
        context,
        onError: (_, _) {},
      );
    }
  }

  /// 连续阅读预加载：以 (章节索引, 章节内索引) 为中心，预加载相邻图片（跨章）。
  void _preloadChainImages(int chapterIndex, int localIndex, {int range = 2}) {
    if (_chain.isEmpty) return;
    final chapter = _chain[chapterIndex.clamp(0, _chain.length - 1)];
    if (chapter.isDownloaded) return;
    for (int offset = -range; offset <= range; offset++) {
      var ci = chapterIndex;
      var li = localIndex + offset;
      // 处理跨章回溯/前进
      while (li < 0 && ci > 0) {
        ci--;
        li += _chain[ci].contents.length;
      }
      while (li >= _chain[ci].contents.length && ci < _chain.length - 1) {
        li -= _chain[ci].contents.length;
        ci++;
      }
      if (li < 0 || li >= _chain[ci].contents.length) continue;
      final chap = _chain[ci];
      if (chap.isDownloaded) continue;
      precacheImage(
        CachedNetworkImageProvider(
          chap.contents[li],
          cacheManager: _readerImageCacheManager,
        ),
        context,
        onError: (_, _) {},
      );
    }
  }

  // ── 公共图片组件 ──
  //
  // 为支持连续阅读拼接多章图片，图片构建方法以 (chapter, localIndex) 定位图片，
  // 以 retryKey（非连续时等于 localIndex，连续时为全局索引）作为重试/版本状态键，
  // 避免不同章节的同名索引互相覆盖重试状态。

  void _retryImage(ChapterDetail chapter, int localIndex, int retryKey) {
    _setState(() {
      _imageRetryCounts.remove(retryKey);
      _imageRetryTokens.remove(retryKey);
      _imageReloadVersions[retryKey] =
          (_imageReloadVersions[retryKey] ?? 0) + 1;
    });
  }

  void _clearImageRetryState(int retryKey) {
    if (!_imageRetryCounts.containsKey(retryKey) &&
        !_imageRetryTokens.containsKey(retryKey)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setState(() {
        _imageRetryCounts.remove(retryKey);
        _imageRetryTokens.remove(retryKey);
      });
    });
  }

  /// 记录单张图片的原始尺寸，供占位符/错误 Widget 估算高度。
  void _recordImageNaturalSize(String source, Size size) {
    if (size.isEmpty) return;
    // 重新插入可刷新插入序，避免活跃图片被 LRU 误淘汰。
    _imageNaturalSizes.remove(source);
    _imageNaturalSizes[source] = size;
    while (_imageNaturalSizes.length > _ReaderPageState._maxImageNaturalSizes) {
      _imageNaturalSizes.remove(_imageNaturalSizes.keys.first);
    }
  }

  /// 解析并缓存图片原始尺寸，完成后释放 ImageInfo / listener。
  void _resolveAndCacheImageSize(ImageProvider provider, String source) {
    if (_imageNaturalSizes.containsKey(source)) return;
    late final ImageStreamListener listener;
    final stream = provider.resolve(ImageConfiguration.empty);
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        final size = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        info.dispose();
        _recordImageNaturalSize(source, size);
      },
      onError: (_, _) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  /// 从已加载的图片中统计出最常见的宽高比（频率最高的桶）。
  /// 返回 null 表示尚无数据。
  double? get _typicalImageAspectRatio {
    if (_imageNaturalSizes.isEmpty) return null;
    // 按宽高比分桶（精度 0.01），取出现次数最多的桶的中位数。
    const bucketStep = 0.01;
    final buckets = <int, List<double>>{};
    for (final size in _imageNaturalSizes.values) {
      if (size.width <= 0) continue;
      final ratio = size.height / size.width;
      final bucket = (ratio / bucketStep).round();
      buckets.putIfAbsent(bucket, () => []).add(ratio);
    }
    if (buckets.isEmpty) return null;
    int maxCount = 0;
    int? maxBucket;
    for (final entry in buckets.entries) {
      if (entry.value.length > maxCount) {
        maxCount = entry.value.length;
        maxBucket = entry.key;
      }
    }
    if (maxBucket == null) return null;
    // 返回该桶中所有比例的均值
    final ratios = buckets[maxBucket]!;
    return ratios.fold(0.0, (sum, r) => sum + r) / ratios.length;
  }

  /// 在竖向滚动模式下，为指定图片源返回占位符的预估高度。
  /// 如果该图片自身已有缓存尺寸直接用；否则用当前最常见宽高比估算；
  /// 最后兜底返回屏幕高度 × 1.35（典型竖图比例）。
  double _estimatedPlaceholderHeight(String imageSource) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cached = _imageNaturalSizes[imageSource];
    if (cached != null && cached.width > 0) {
      return screenWidth * (cached.height / cached.width);
    }
    final typicalRatio = _typicalImageAspectRatio;
    if (typicalRatio != null && typicalRatio > 0) {
      return screenWidth * typicalRatio;
    }
    // 兜底：典型竖图宽高比约 1.35
    return screenWidth * 1.35;
  }

  /// 在横向滚动模式下，为指定图片源返回占位符的预估宽度。
  /// 高度由外层 SizedBox 约束为视口高度，但宽度无约束——占位符会
  /// 塌缩成加载指示器的宽度，图片加载完成后宽度突变导致页面跳动。
  /// 与竖向模式同理：优先用该图缓存尺寸，其次用最常见宽高比估算，
  /// 兜底为视口高度 ÷ 1.35（典型竖图比例）。
  double _estimatedPlaceholderWidth(String imageSource) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final cached = _imageNaturalSizes[imageSource];
    if (cached != null && cached.height > 0) {
      return viewportHeight * (cached.width / cached.height);
    }
    final typicalRatio = _typicalImageAspectRatio;
    if (typicalRatio != null && typicalRatio > 0) {
      return viewportHeight / typicalRatio;
    }
    // 兜底：典型竖图宽高比约 1.35
    return viewportHeight / 1.35;
  }

  void _scheduleImageRetry(int retryKey) {
    final attempts = _imageRetryCounts[retryKey] ?? 0;
    final retryLimit = _user.imageRetryCount;
    if (attempts >= retryLimit) return;

    final version = _imageReloadVersions[retryKey] ?? 0;
    final token = '$version-$attempts';
    if (_imageRetryTokens[retryKey] == token) return;
    _imageRetryTokens[retryKey] = token;

    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final currentVersion = _imageReloadVersions[retryKey] ?? 0;
      if (currentVersion != version) return;

      _setState(() {
        _imageRetryCounts[retryKey] = attempts + 1;
        _imageRetryTokens.remove(retryKey);
        _imageReloadVersions[retryKey] = currentVersion + 1;
      });
    });
  }

  Future<void> _copyImageUrl(ChapterDetail chapter, int localIndex) async {
    final imageSource = localIndex < chapter.contents.length
        ? chapter.contents[localIndex]
        : null;
    if (imageSource == null || imageSource.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: imageSource));
    if (!mounted) return;
    showToast(
      context,
      chapter.isDownloaded
          ? AppLocalizations.of(context)!.readerImagePathCopied
          : AppLocalizations.of(context)!.readerImageUrlCopied,
    );
  }

  Future<void> _openImageViewer(ChapterDetail chapter, int localIndex) async {
    if (localIndex < 0 || localIndex >= chapter.contents.length) return;

    // 打开图片查看器期间暂停自动滚动，与设置面板/评论面板保持一致
    _pauseAutoScrollForOverlay();
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => _ReaderImageViewer(
          imageSource: chapter.contents[localIndex],
          isDownloaded: chapter.isDownloaded,
          cacheManager: _readerImageCacheManager,
          pageNumber: localIndex + 1,
          pageCount: chapter.contents.length,
        ),
      ),
    );
    if (!mounted) return;
    _resumeAutoScrollAfterOverlay();
    if (_showToolbar) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        ),
      );
    } else {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
  }

  Widget _buildReaderImageGesture(
    ChapterDetail chapter,
    int localIndex, {
    int? retryKey,
    bool zoomActive = true,
  }) {
    final key = retryKey ?? localIndex;
    Widget image = _buildImage(chapter, localIndex, retryKey: key);
    if (_isPageMode) {
      // 翻页模式：捏合缩放当前页单图；滚动模式由 _buildScrollMode 的
      // 整视图缩放负责。双击进查看器的手势在更外层，不受缩放影响。
      image = PinchZoomable(
        active: zoomActive,
        onZoomChanged: _handlePageZoomChanged,
        child: image,
      );
    }
    final imageGesture = _ReaderImageGesture(
      key: ValueKey('reader-image-${chapter.uuid}-$localIndex'),
      onSingleTap: _isPageMode
          ? _handlePageModeTapAt
          : (_) => _handleReadingSurfaceTap(),
      onDoubleTap: () => _openImageViewer(chapter, localIndex),
      child: image,
    );
    if (readerLongPressZoomTargetForMode(isPageMode: _isPageMode) !=
        ReaderLongPressZoomTarget.page) {
      return imageGesture;
    }
    return _buildLongPressZoomSurface(
      imageGesture,
      active: zoomActive && !_pageImageZoomed,
    );
  }

  Widget _buildImage(ChapterDetail chapter, int localIndex, {int? retryKey}) {
    final cs = Theme.of(context).colorScheme;
    final key = retryKey ?? localIndex;
    final imageSource = chapter.contents[localIndex];
    final useFullViewport = _isPageMode || _isHorizontalScrollMode;
    final imageFit = _isHorizontalScrollMode
        ? BoxFit.fitHeight
        : (useFullViewport ? BoxFit.contain : BoxFit.fitWidth);
    final screenSize = MediaQuery.sizeOf(context);
    final memCacheWidth = _isHorizontalScrollMode
        ? (screenSize.height * MediaQuery.devicePixelRatioOf(context)).round()
        : (screenSize.width * MediaQuery.devicePixelRatioOf(context)).round();

    // 竖向滚动模式下，占位符使用预估高度以防页面跳动；翻页模式占满
    // viewport 不需要估算。横向滚动模式高度虽由外层 SizedBox 约束，
    // 但宽度无约束，占位符会塌缩成加载指示器的宽度，图片加载完成后
    // 宽度突变导致页面跳动，因此需要预估宽度。
    final estimatedPlaceholderH = !useFullViewport
        ? _estimatedPlaceholderHeight(imageSource)
        : null;
    final estimatedPlaceholderW = _isHorizontalScrollMode
        ? _estimatedPlaceholderWidth(imageSource)
        : null;

    Widget image;

    if (chapter.isDownloaded) {
      _clearImageRetryState(key);
      image = Image.file(
        File(imageSource),
        fit: imageFit,
        width: _isHorizontalScrollMode ? null : double.infinity,
        height: useFullViewport ? double.infinity : null,
        // 与网络图一致：按屏幕尺寸限制解码，避免原图像素常驻内存。
        cacheWidth: _isHorizontalScrollMode ? null : memCacheWidth,
        cacheHeight: _isHorizontalScrollMode ? memCacheWidth : null,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          // 图片首帧渲染后，异步解析原始尺寸并缓存。
          if (frame == 0 && !_imageNaturalSizes.containsKey(imageSource)) {
            _resolveAndCacheImageSize(
              FileImage(File(imageSource)),
              imageSource,
            );
          }
          // 解码是异步的：首帧前 Image.file 尺寸为 0，而 0 尺寸 item 不会
          // 消耗列表的缓存预算，整章 item 会被一次性构建并解码，滚动位置的
          // 估算随之失真，快速滑动时被连续修正推到远超手势距离的页码。
          // 与网络图占位同理，首帧前用预估尺寸占位。
          if (frame == null) {
            return Container(
              width: _isHorizontalScrollMode
                  ? estimatedPlaceholderW
                  : double.infinity,
              height: useFullViewport
                  ? double.infinity
                  : (estimatedPlaceholderH ?? 400),
              // 与背景同色即视觉隐形；保留 ColoredBox 是为了让加载区域
              // 维持点击热区（透明时点击会穿透到列表手势）。
              color: ReaderChrome.surface,
            );
          }
          return child;
        },
        errorBuilder: (_, _, _) => Container(
          width: estimatedPlaceholderW,
          height: estimatedPlaceholderH ?? 400,
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, color: cs.onSurfaceVariant, size: 48),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppLocalizations.of(context)!.readerLocalImageMissing,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.tonalIcon(
                  onPressed: () => _copyImageUrl(chapter, localIndex),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: Text(
                    AppLocalizations.of(context)!.readerCopyImagePath,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      image = CachedNetworkImage(
        key: ValueKey(
          '${chapter.uuid}-$localIndex-${_imageReloadVersions[key] ?? 0}',
        ),
        imageUrl: imageSource,
        cacheManager: _readerImageCacheManager,
        fit: imageFit,
        memCacheWidth: memCacheWidth,
        width: _isHorizontalScrollMode ? null : double.infinity,
        height: useFullViewport ? double.infinity : null,
        // 交叉淡出期间 octo_image 会把真图居中叠在占位区域上，占位尺寸
        // 估算偏大时已读侧留缝、淡出结束尺寸骤变引发跳动。过渡缩短到
        // 250ms 减少灰罩停留，并配合过渡撑块让真图贴住已读侧边缘，
        // 尺寸纠正只落在未读侧（见 _imageRevealAlignment）。
        fadeInDuration: _ReaderPageState._imageTransitionDuration,
        fadeOutDuration: _ReaderPageState._imageTransitionDuration,
        imageBuilder: (_, imageProvider) {
          _clearImageRetryState(key);
          // 图片加载成功后，异步解析其原始尺寸并缓存。
          _resolveAndCacheImageSize(imageProvider, imageSource);
          final loadedImage = Image(
            image: imageProvider,
            fit: imageFit,
            width: _isHorizontalScrollMode ? null : double.infinity,
            height: useFullViewport ? double.infinity : null,
          );
          // 翻页模式图片占满视口、尺寸恒定，无需过渡撑块。
          if (estimatedPlaceholderW == null && estimatedPlaceholderH == null) {
            return loadedImage;
          }
          return ImageRevealHold(
            alignment: _imageRevealAlignment,
            holdWidth: estimatedPlaceholderW,
            holdHeight: estimatedPlaceholderH,
            holdDuration: _ReaderPageState._imageTransitionDuration,
            child: loadedImage,
          );
        },
        placeholder: (_, _) => Container(
          width: estimatedPlaceholderW,
          height: estimatedPlaceholderH ?? 400,
          // 与背景同色即视觉隐形；保留 ColoredBox 是为了让加载区域
          // 维持点击热区（透明时点击会穿透到列表手势）。
          color: ReaderChrome.surface,
          child: const Center(child: ExpressiveLoadingIndicator()),
        ),
        errorWidget: (_, _, _) {
          final attempts = _imageRetryCounts[key] ?? 0;
          final retryLimit = _user.imageRetryCount;
          final canAutoRetry = attempts < retryLimit;
          if (canAutoRetry) {
            _scheduleImageRetry(key);
          }
          final pageLabel = '${chapter.name} · ${localIndex + 1}';
          final failedLabel =
              '${AppLocalizations.of(context)!.loadingFailed}\n$pageLabel';

          return Container(
            width: estimatedPlaceholderW,
            height: estimatedPlaceholderH ?? 400,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.broken_image,
                    color: cs.onSurfaceVariant,
                    size: 48,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    canAutoRetry
                        ? AppLocalizations.of(
                            context,
                          )!.readerImageRetrying(attempts + 1, retryLimit)
                        : failedLabel,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                  if (!canAutoRetry) ...[
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.tonalIcon(
                      onPressed: () => _retryImage(chapter, localIndex, key),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(
                        AppLocalizations.of(context)!.readerReloadImage,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.tonalIcon(
                      onPressed: () => _copyImageUrl(chapter, localIndex),
                      icon: const Icon(Icons.copy_all_outlined, size: 18),
                      label: Text(
                        AppLocalizations.of(context)!.readerCopyImageUrl,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    }
    // 深色模式亮度遮罩
    if (_isDarkMode && _user.readerDimming > 0) {
      image = Stack(
        children: [
          image,
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: ReaderChrome.dimOverlay(_user.readerDimming),
              ),
            ),
          ),
        ],
      );
    }
    return image;
  }
}
