part of '../novel_reader_page.dart';

extension _NovelReaderViewPart on _NovelReaderPageState {
  /// 状态组件：与漫画阅读器同一套摆放规则（六位 + 中间对齐），
  /// 工具栏隐藏时显示；点按唤出工具栏。
  Widget _buildStatusOverlay() {
    // 0左上 1顶中 2右上 3右下 4底中 5左下
    final position = _statusSettings.statusOverlayPosition;
    final isTop = position < 3;
    final isLeft = {0: true, 5: true}[position] ?? false;
    final isCenter = position == 1 || position == 4;
    return Positioned(
      key: const ValueKey('novel-status-overlay'),
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: isCenter || isLeft ? 0 : null,
      right: isCenter || !isLeft ? 0 : null,
      child: Visibility(
        visible: !_toolbarVisible,
        maintainState: true,
        child: TickerMode(
          enabled: !_toolbarVisible,
          child: Semantics(
            button: true,
            label: AppLocalizations.of(context)!.novelReaderShowToolbar,
            child: InkWell(
              key: const ValueKey('novel-reader-show-toolbar'),
              onTap: () => _setToolbarVisible(true),
              child: isCenter
                  ? Align(
                      alignment: isTop
                          ? Alignment.topCenter
                          : Alignment.bottomCenter,
                      child: _statusOverlayChild(),
                    )
                  : _statusOverlayChild(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusOverlayChild() => RepaintBoundary(
    child: ValueListenableBuilder<int>(
      valueListenable: _locationRevision,
      builder: (context, revision, child) {
        final palette = NovelReaderPalette.resolve(
          _settings,
          MediaQuery.platformBrightnessOf(context),
        );
        return ReaderStatusOverlay(
          // 浮层进度降为一位小数（紧凑、与电量数字区分）；工具栏滑杆
          // 标签仍用两位小数的 _progressLabel。
          progressLabel: _overlayProgressLabel(_location?.progress ?? 0),
          chapterLabel: _chapterName(AppLocalizations.of(context)!),
          prefs: _statusSettings,
          // 未手动指定颜色时，状态组件底色/字色跟随当前阅读主题。
          defaultForeground: palette.foreground,
          defaultBackground: palette.background,
          // 角落位 Positioned 只锚一侧、约束无界：传屏幕宽让章节名的
          // Flexible 有界，超长才会截断。
          maxWidth: MediaQuery.sizeOf(context).width,
        );
      },
    ),
  );

  String _overlayProgressLabel(double progress) {
    final percent = progress * 100;
    // 未到结尾不得显示成 100%；一位小数。
    final capped = progress >= 1
        ? 100.0
        : percent > 99.9
        ? 99.9
        : percent;
    return '${capped.toStringAsFixed(1)}%';
  }

  Widget _buildHeader() {
    final l10n = AppLocalizations.of(context)!;
    final bookName = _content?.detail.book.name ?? _fallbackName;
    final isBookmarked = _bookmarksLoaded && _isBookmarked;
    return ColoredBox(
      color: ReaderChrome.surface,
      // 工具栏位于全屏 Stack 顶层（覆盖到状态栏底下），内部避开系统栏。
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('novel-reader-back'),
                tooltip: l10n.novelReaderBack,
                color: ReaderChrome.onSurface,
                onPressed: _back,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  bookName.isEmpty ? l10n.novelReaderTitle : bookName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: ReaderChrome.onSurface,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('novel-reader-bookmark'),
                tooltip: isBookmarked ? l10n.bookmarkRemove : l10n.bookmarkAdd,
                // 与漫画阅读器一致，书签高亮不随正文配色改变。
                color: isBookmarked
                    ? Colors.amberAccent
                    : ReaderChrome.onSurface,
                onPressed: _loading || _bookmarking || _location == null
                    ? null
                    : _toggleBookmark,
                icon: Icon(
                  isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    final document = _document;
    final request = _request;
    if (_loading) return const Center(child: ExpressiveLoadingIndicator());
    if (_error != null) return _buildError();
    if (document == null || document.itemCount == 0) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ErrorRetryView(
            icon: Icons.menu_book_outlined,
            message: l10n.novelReaderEmptyVolume,
            onRetry: () => unawaited(
              _loadVolume(_volumeId, anchor: _target, refresh: true),
            ),
          ),
        ),
      );
    }
    final palette = NovelReaderPalette.resolve(
      _settings,
      MediaQuery.platformBrightnessOf(context),
    );
    void onPosition(NovelReaderLocation location) {
      if (_request == request && identical(_document, document)) {
        _recordLocation(location);
      }
    }

    if (_paged) {
      return NovelReaderPageView(
        key: _pageViewKey,
        document: document,
        settings: _settings,
        palette: palette,
        target: _target,
        jumpRevision: _jumpRevision,
        emptyChapterText: l10n.novelReaderEmptyChapter,
        contentPadding: _systemPadding ?? EdgeInsets.zero,
        onPosition: onPosition,
        toolbarVisible: _toolbarVisible,
        onTap: () => _setToolbarVisible(!_toolbarVisible),
        onParagraphLongPress: (paragraph, position) =>
            unawaited(_showParagraphMenu(paragraph, position)),
        highlight: _highlight,
        highlightOpacity: _highlightFade,
        onPageTurned: () {
          _clearHighlight();
          _setToolbarVisible(false);
        },
        // 卷末继续翻页进入下一卷首页；卷首回翻进入上一卷末页。
        onBoundary: (forward) => _stepVolume(forward ? 1 : -1),
      );
    }
    return NovelReaderViewport(
      key: _viewportKey,
      document: document,
      settings: _settings,
      contentPadding: _systemPadding ?? EdgeInsets.zero,
      palette: palette,
      target: _target,
      jumpRevision: _jumpRevision,
      contentRevision: _contentRevision,
      seam: _buildSeam(),
      headSeam: _buildHeadSeam(),
      onApproachEnd: _prefetchNextVolume,
      onReachSeam: () => unawaited(_appendNextVolume()),
      onApproachStart: _prefetchPreviousVolume,
      onReachStart: () => unawaited(_prependPreviousVolume()),
      highlight: _highlight,
      highlightOpacity: _highlightFade,
      onPosition: onPosition,
      onTap: () => _setToolbarVisible(!_toolbarVisible),
      onParagraphLongPress: (paragraph, position) =>
          unawaited(_showParagraphMenu(paragraph, position)),
      onScroll: () {
        _clearHighlight();
        _setToolbarVisible(false);
      },
    );
  }

  String _progressLabel(double progress) {
    final percent = progress * 100;
    // 四舍五入到两位小数，但未到结尾不得显示成 100%。
    final capped = progress >= 1
        ? 100.0
        : percent > 99.99
        ? 99.99
        : percent;
    return '${capped.toStringAsFixed(2)}%';
  }

  /// 滑杆落点：滑杆坐标是当前卷内的 item 下标，换算成卷栈里的绝对下标。
  void _jumpToLocalItem(int local) {
    final document = _document;
    if (document == null || document.itemCount == 0) return;
    final item = (_location?.itemIndex ?? document.itemFor(_target)).clamp(
      0,
      document.itemCount - 1,
    );
    final absolute = item - document.localItemFor(item) + local;
    _jumpTo(document.anchorFor(absolute.clamp(0, document.itemCount - 1)));
  }

  String _chapterName(AppLocalizations l10n) {
    final document = _document;
    final item = _location?.itemIndex ?? 0;
    if (document == null || document.itemCount == 0) {
      return _accessDetail?.volume.name ?? l10n.novelReaderTitle;
    }
    final entry = document.paragraphAt(item).entry;
    return entry.name.isEmpty
        ? l10n.novelReaderUnnamedChapter(document.entrySlotFor(item) + 1)
        : entry.name;
  }

  Widget _buildToolbar() {
    final l10n = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;
    final document = _document;
    final total = document?.itemCount ?? 0;
    // 进度按当前卷计算：连续阅读跨卷后滑杆与百分比回到新卷的 0..1。
    final count = document == null
        ? 0
        : document.localItemCountFor(
            (_location?.itemIndex ?? document.itemFor(_target)).clamp(
              0,
              math.max(0, total - 1),
            ),
          );
    final current = document == null
        ? 0
        : _sliderValue?.round() ??
              document.localItemFor(
                (_location?.itemIndex ?? document.itemFor(_target)).clamp(
                  0,
                  math.max(0, total - 1),
                ),
              );
    final value = _sliderValue ?? current.toDouble();
    final progress = _sliderValue != null
        ? (count > 1 ? value.round() / (count - 1) : 0.0)
        : (_location?.progress ?? (count > 1 ? current / (count - 1) : 0.0));
    final progressLabel = _progressLabel(progress);
    return ColoredBox(
      color: ReaderChrome.surface,
      // 工具栏位于全屏 Stack 底部顶层（延伸到导航栏底下），内部避开系统栏。
      child: SafeArea(
        top: false,
        child: IconTheme(
          data: const IconThemeData(color: ReaderChrome.onSurface),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Row(
                    children: [
                      if (_offline)
                        const Padding(
                          padding: EdgeInsets.only(right: AppSpacing.xs),
                          child: Icon(Icons.offline_pin_outlined, size: 16),
                        ),
                      Expanded(
                        child: Text(
                          _chapterName(l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: ReaderChrome.onSurfaceMuted),
                        ),
                      ),
                      Text(
                        progressLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ReaderChrome.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                SliderTheme(
                  // 与漫画阅读器底栏进度条同一套配色/粗细/滑块；唯一差别是
                  // 小说的「刻度」不是等距分页，而是按章节段落偏移定位的圆点。
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    trackShape: NovelChapterSliderTrackShape(
                      chapterStarts: document == null
                          ? const []
                          : document.chapterStartsFor(
                              (_location?.itemIndex ?? 0).clamp(
                                0,
                                math.max(0, total - 1),
                              ),
                            ),
                      activeColor: primary,
                      inactiveColor: ReaderChrome.trackInactive,
                    ),
                    activeTrackColor: primary,
                    inactiveTrackColor: ReaderChrome.trackInactive,
                    thumbColor: primary,
                    overlayColor: primary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    key: const ValueKey('novel-reader-progress'),
                    value: value.clamp(0, count > 1 ? count - 1.0 : 1.0),
                    max: count > 1 ? count - 1.0 : 1,
                    label: progressLabel,
                    onChanged: count > 1 && !_loading
                        ? _onSliderValueChanged
                        : null,
                    onChangeEnd: count > 1 && !_loading
                        ? (value) => _jumpToLocalItem(value.round())
                        : null,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      key: const ValueKey('novel-reader-previous'),
                      tooltip: l10n.novelReaderPrevious,
                      onPressed: _canStepVolume(-1)
                          ? () => _stepVolume(-1)
                          : null,
                      // 与漫画阅读器底栏一致：颜色显式指定，禁用态仍可见。
                      icon: Icon(
                        Icons.skip_previous,
                        color: _canStepVolume(-1)
                            ? ReaderChrome.onSurface
                            : ReaderChrome.onSurfaceFaint,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('novel-reader-contents'),
                      tooltip: l10n.novelReaderContents,
                      onPressed: _showContents,
                      icon: const Icon(Icons.format_list_bulleted),
                    ),
                    IconButton(
                      key: const ValueKey('novel-reader-focus-mode'),
                      tooltip: l10n.novelReaderFocusMode,
                      // 激活高亮与书签按钮同一先例：不随正文配色改变。
                      color: _settings.focusModeEnabled
                          ? Colors.amberAccent
                          : ReaderChrome.onSurface,
                      onPressed: _loading
                          ? null
                          : () => _changeSettings(
                              _settings.copyWith(
                                focusModeEnabled: !_settings.focusModeEnabled,
                              ),
                            ),
                      icon: const Icon(Icons.center_focus_strong),
                    ),
                    IconButton(
                      key: const ValueKey('novel-reader-settings'),
                      tooltip: l10n.novelReaderSettings,
                      onPressed: _loading ? null : _showSettings,
                      icon: const Icon(Icons.settings_outlined),
                    ),
                    IconButton(
                      key: const ValueKey('novel-reader-next'),
                      tooltip: l10n.novelReaderNext,
                      onPressed: _canStepVolume(1)
                          ? () => _stepVolume(1)
                          : null,
                      icon: Icon(
                        Icons.skip_next,
                        color: _canStepVolume(1)
                            ? ReaderChrome.onSurface
                            : ReaderChrome.onSurfaceFaint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final l10n = AppLocalizations.of(context)!;
    final error = _error;
    final locked = _accessDetail?.isLocked ?? false;
    final unauthorized = error is NovelApiException && error.isUnauthorized;
    final canLogin =
        unauthorized ||
        (error is NovelAccessException &&
            (!error.detail.isLoggedIn || !_api.hasCopyToken));
    final message = error is NovelDownloadUnavailableException
        ? l10n.novelDownloadUnavailable
        : locked
        ? l10n.novelReaderLocked
        : error is _NoCachedVolume
        ? l10n.novelReaderNoCache
        : error is NovelAccessException
        ? l10n.novelReaderEmptyVolume
        : unauthorized
        ? l10n.novelReaderLoginRequired
        : novelErrorMessage(error, fallback: l10n.novelReaderLoadFailed);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ErrorRetryView(
            icon: locked ? Icons.lock_outline : Icons.cloud_off_outlined,
            message: message,
            onRetry: () => unawaited(
              _loadVolume(_volumeId, anchor: _target, refresh: true),
            ),
          ),
          if (canLogin)
            TextButton.icon(
              key: const ValueKey('novel-reader-login'),
              onPressed: _login,
              icon: const Icon(Icons.login),
              label: Text(l10n.novelReaderCopyLogin),
            ),
          if (_source.localOnly || widget.localOnly)
            TextButton.icon(
              key: const ValueKey('novel-reader-open-downloads'),
              onPressed: () async {
                final session = _session;
                await context.pushNamed(
                  AppRoutes.downloadCenter,
                  queryParameters: {'tab': '2'},
                );
                if (_active(session)) {
                  await _loadVolume(_volumeId, anchor: _target);
                }
              },
              icon: const Icon(Icons.download_outlined),
              label: Text(l10n.downloadCenterTitle),
            )
          else
            TextButton.icon(
              key: const ValueKey('novel-reader-open-cache'),
              onPressed: () => unawaited(
                _loadVolume(_volumeId, anchor: _target, cachedOnly: true),
              ),
              icon: const Icon(Icons.offline_pin_outlined),
              label: Text(l10n.novelReaderOpenCache),
            ),
        ],
      ),
    );
  }
}
