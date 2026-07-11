part of '../anime_player_page.dart';

class _PlayerControlButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final double extent;
  final VoidCallback? onPressed;

  const _PlayerControlButton({
    required this.tooltip,
    required this.icon,
    required this.iconSize,
    required this.extent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: extent,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: iconSize,
        color: Colors.white,
        disabledColor: Colors.white38,
      ),
    );
  }
}


/// 播放器栏 SVG 图标（viewBox 统一 24x24）
class _PlayerSvgControlButton extends StatelessWidget {
  final String tooltip;
  final String asset;
  final double iconSize;
  final double extent;
  final VoidCallback? onPressed;

  const _PlayerSvgControlButton({
    required this.tooltip,
    required this.asset,
    required this.iconSize,
    required this.extent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: extent,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: iconSize,
        icon: SvgPicture.asset(
          asset,
          width: iconSize,
          height: iconSize,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
      ),
    );
  }
}


class _VideoPlayerSurface extends StatefulWidget {
  final VideoController controller;
  final bool fullscreen;
  final VoidCallback onSkipForward;
  final VoidCallback onDanmakuSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onToggleDanmaku;
  final List<AnimeChapter> chapters;
  final String currentChapterUuid;
  final ValueChanged<AnimeChapter> onChapterSelected;
  final bool danmakuVisible;
  final Widget? danmakuView;
  final String title;

  const _VideoPlayerSurface({
    required this.controller,
    required this.fullscreen,
    required this.onSkipForward,
    required this.onDanmakuSettings,
    required this.onFullscreen,
    required this.onToggleDanmaku,
    required this.chapters,
    required this.currentChapterUuid,
    required this.onChapterSelected,
    required this.danmakuVisible,
    required this.title,
    this.danmakuView,
  });

  @override
  State<_VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends State<_VideoPlayerSurface> {
  static const _controlsAutoHideDelay = Duration(seconds: 3);

  bool _controlsVisible = true;
  bool _playlistVisible = false;
  Timer? _hideControlsTimer;

  // Slider 拖动状态
  bool _isSliderDragging = false;
  double _sliderDragValue = 0.0;

  // 手势处理状态
  double? _dragStartX;
  Duration? _dragTargetPosition;
  bool _isDraggingProgress = false;

  double? _dragStartY;
  bool _isDraggingVolume = false;
  bool _isDraggingBrightness = false;
  double _initialVolume = 0;
  double _initialBrightness = 0;
  double? _currentVolume;
  double? _currentBrightness;

  VideoController get controller => widget.controller;
  Player get player => widget.controller.player;

  @override
  void initState() {
    super.initState();
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  @override
  void didUpdateWidget(covariant _VideoPlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    setState(() => _controlsVisible = true);
    _startControlsAutoHideTimer();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _startControlsAutoHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(_controlsAutoHideDelay, () {
      if (!mounted || !player.state.playing || _playlistVisible) return;
      setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (!_controlsVisible || !player.state.playing) {
      _hideControlsTimer?.cancel();
      _hideControlsTimer = null;
      return;
    }
    _startControlsAutoHideTimer();
  }

  void _showControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    if (player.state.playing) {
      _startControlsAutoHideTimer();
    }
  }

  void _togglePlaylist() {
    setState(() {
      _controlsVisible = true;
      _playlistVisible = !_playlistVisible;
    });
    if (!_playlistVisible && player.state.playing) {
      _startControlsAutoHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _hidePlaylist() {
    if (!_playlistVisible) return;
    setState(() => _playlistVisible = false);
    if (player.state.playing) {
      _startControlsAutoHideTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const controlButtonSize = 24.0;
    const controlButtonExtent = 40.0;
    final currentIndex = widget.chapters.indexWhere(
      (c) => c.uuid == widget.currentChapterUuid,
    );
    final prevChapter = currentIndex > 0
        ? widget.chapters[currentIndex - 1]
        : null;
    final nextChapter =
        currentIndex >= 0 && currentIndex < widget.chapters.length - 1
        ? widget.chapters[currentIndex + 1]
        : null;

    return StreamBuilder<Object>(
      stream: player.stream.position,
      builder: (context, _) {
        final state = player.state;
        final duration = state.duration;
        final position = state.position;
        final playing = state.playing;
        final progress = duration.inMilliseconds <= 0
            ? 0.0
            : (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              );

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Video(controller: controller, controls: NoVideoControls),
              ),
              if (widget.danmakuView != null)
                Positioned.fill(
                  child: IgnorePointer(child: widget.danmakuView),
                ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  onDoubleTap: _togglePlay,
                  onHorizontalDragStart: (details) {
                    _dragStartX = details.globalPosition.dx;
                    _dragTargetPosition = player.state.position;
                    _isDraggingProgress = true;
                    _showControls();
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_dragStartX == null) return;
                    final delta = details.globalPosition.dx - _dragStartX!;
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    // 左右滑动控制进度，滑动全屏距离相当于视频总时长的 1/2
                    final totalDuration = player.state.duration;
                    if (totalDuration == Duration.zero) return;

                    final deltaMs =
                        (delta / screenWidth) *
                        totalDuration.inMilliseconds *
                        0.5;
                    final targetMs =
                        player.state.position.inMilliseconds + deltaMs.toInt();
                    _dragTargetPosition = Duration(
                      milliseconds: targetMs.clamp(
                        0,
                        totalDuration.inMilliseconds,
                      ),
                    );
                    setState(() {});
                  },
                  onHorizontalDragEnd: (details) {
                    if (_isDraggingProgress && _dragTargetPosition != null) {
                      player.seek(_dragTargetPosition!);
                    }
                    _isDraggingProgress = false;
                    _dragStartX = null;
                    _dragTargetPosition = null;
                  },
                  onVerticalDragStart: (details) async {
                    _dragStartY = details.globalPosition.dy;
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    if (details.globalPosition.dx > screenWidth / 2) {
                      _isDraggingVolume = true;
                      _initialVolume = player.state.volume / 100.0;
                    } else {
                      _isDraggingBrightness = true;
                      try {
                        _initialBrightness =
                            await ScreenBrightness().application;
                      } catch (_) {
                        _initialBrightness = 0.5;
                      }
                    }
                  },
                  onVerticalDragUpdate: (details) async {
                    if (_dragStartY == null) return;
                    final delta = _dragStartY! - details.globalPosition.dy;
                    final screenHeight = MediaQuery.sizeOf(context).height;
                    final ratio = delta / (screenHeight * 0.8);

                    if (_isDraggingVolume) {
                      final newVolume = (_initialVolume + ratio).clamp(
                        0.0,
                        1.0,
                      );
                      unawaited(player.setVolume(newVolume * 100.0));
                      setState(() => _currentVolume = newVolume);
                    } else if (_isDraggingBrightness) {
                      final newBrightness = (_initialBrightness + ratio).clamp(
                        0.0,
                        1.0,
                      );
                      try {
                        await ScreenBrightness().setApplicationScreenBrightness(
                          newBrightness,
                        );
                      } catch (e, stack) {
                        unawaited(
                          AppLogger.instance.recordWarning(
                            e,
                            stackTrace: stack,
                            source: 'player_controls.set_brightness',
                          ),
                        );
                      }
                      setState(() => _currentBrightness = newBrightness);
                    }
                  },
                  onVerticalDragEnd: (details) {
                    _isDraggingVolume = false;
                    _isDraggingBrightness = false;
                    _dragStartY = null;
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        setState(() {
                          _currentVolume = null;
                          _currentBrightness = null;
                        });
                      }
                    });
                  },
                ),
              ),
              if (_isDraggingProgress && _dragTargetPosition != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_formatDuration(_dragTargetPosition!)} / ${_formatDuration(player.state.duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ),
              if (_currentVolume != null || _currentBrightness != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _currentVolume != null
                              ? (_currentVolume! <= 0
                                    ? Icons.volume_mute
                                    : Icons.volume_up)
                              : Icons.brightness_6,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${((_currentVolume ?? _currentBrightness!) * 100).toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!playing && _controlsVisible)
                Center(
                  child: IconButton.filledTonal(
                    onPressed: _togglePlay,
                    icon: const Icon(Icons.play_arrow),
                    iconSize: widget.fullscreen ? 56 : 44,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              if (widget.fullscreen && _playlistVisible)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _hidePlaylist,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SafeArea(
                        left: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                          child: _PlayerPlaylistOverlay(
                            chapters: widget.chapters,
                            currentChapterUuid: widget.currentChapterUuid,
                            onSelected: (chapter) {
                              _hidePlaylist();
                              widget.onChapterSelected(chapter);
                            },
                            onClose: _hidePlaylist,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // 顶部栏：非全屏与全屏都显示
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Listener(
                      onPointerDown: (_) => _showControls(),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            4,
                            widget.fullscreen ? 8 : 4,
                            16,
                            widget.fullscreen ? 16 : 8,
                          ),
                          child: Row(
                            children: [
                              if (widget.fullscreen)
                                IconButton(
                                  tooltip: l10n.animePlayerExitFullscreen,
                                  onPressed: widget.onFullscreen,
                                  icon: const Icon(Icons.arrow_back),
                                  color: Colors.white,
                                )
                              else
                                const SizedBox(width: 8),
                              if (widget.fullscreen) const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: widget.fullscreen ? 16 : 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Listener(
                      onPointerDown: (_) => _showControls(),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            8,
                            22,
                            8,
                            widget.fullscreen ? 16 : 4,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 12,
                                  ),
                                ),
                                child: Slider(
                                  value: _isSliderDragging
                                      ? _sliderDragValue
                                      : progress,
                                  onChanged: (v) {
                                    setState(() {
                                      _isSliderDragging = true;
                                      _sliderDragValue = v;
                                    });
                                    _showControls();
                                  },
                                  onChangeEnd: (v) {
                                    player.seek(
                                      Duration(
                                        milliseconds:
                                            (duration.inMilliseconds * v)
                                                .round(),
                                      ),
                                    );
                                    _isSliderDragging = false;
                                  },
                                  activeColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  inactiveColor: Colors.white38,
                                ),
                              ),
                              Row(
                                children: [
                                  // 左侧：上一集/播放/下一集/快进（全屏）+ 时间
                                  if (widget.fullscreen) ...[
                                    _PlayerControlButton(
                                      tooltip: '上一集',
                                      icon: Icons.skip_previous,
                                      iconSize: controlButtonSize,
                                      extent: controlButtonExtent,
                                      onPressed: prevChapter == null
                                          ? null
                                          : () {
                                              _showControls();
                                              widget.onChapterSelected(
                                                prevChapter,
                                              );
                                            },
                                    ),
                                    const SizedBox(width: 2),
                                    _PlayerControlButton(
                                      tooltip: playing
                                          ? l10n.pauseButton
                                          : l10n.animePlayerPlay,
                                      icon: playing
                                          ? Icons.pause
                                          : Icons.play_arrow,
                                      iconSize: controlButtonSize,
                                      extent: controlButtonExtent,
                                      onPressed: _togglePlay,
                                    ),
                                    const SizedBox(width: 2),
                                    _PlayerControlButton(
                                      tooltip: '下一集',
                                      icon: Icons.skip_next,
                                      iconSize: controlButtonSize,
                                      extent: controlButtonExtent,
                                      onPressed: nextChapter == null
                                          ? null
                                          : () {
                                              _showControls();
                                              widget.onChapterSelected(
                                                nextChapter,
                                              );
                                            },
                                    ),
                                    const SizedBox(width: 4),
                                    _PlayerControlButton(
                                      tooltip: l10n.animePlayerFastForward(
                                        UserManager().animeSkipSeconds,
                                      ),
                                      icon: Icons.more_time,
                                      iconSize: controlButtonSize,
                                      extent: controlButtonExtent,
                                      onPressed: widget.onSkipForward,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    _isSliderDragging
                                        ? '${_formatDuration(Duration(milliseconds: (duration.inMilliseconds * _sliderDragValue).round()))} / ${_formatDuration(duration)}'
                                        : '${_formatDuration(position)} / ${_formatDuration(duration)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: widget.fullscreen ? 14 : 12,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  // 右侧：弹幕/设置/选集（全屏）+ 全屏
                                  if (widget.fullscreen) ...[
                                    _PlayerSvgControlButton(
                                      tooltip: widget.danmakuVisible
                                          ? l10n.animePlayerHideDanmaku
                                          : l10n.playerSettingsShowDanmaku,
                                      asset: widget.danmakuVisible
                                          ? 'assets/danmaku_on.svg'
                                          : 'assets/danmaku_off.svg',
                                      iconSize: controlButtonSize,
                                      extent: controlButtonExtent,
                                      onPressed: widget.onToggleDanmaku,
                                    ),
                                    const SizedBox(width: 4),
                                    _PlayerSvgControlButton(
                                      tooltip: l10n.playerSettingsDanmakuTitle,
                                      asset: 'assets/danmaku_settings.svg',
                                      iconSize: controlButtonSize,
                                      extent: controlButtonExtent,
                                      onPressed: widget.onDanmakuSettings,
                                    ),
                                    const SizedBox(width: 4),
                                    _PlayerControlButton(
                                      tooltip: l10n.animePlayerChapterSelector,
                                      icon: Icons.playlist_play,
                                      iconSize: controlButtonSize,
                                      extent: controlButtonExtent,
                                      onPressed: _togglePlaylist,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  _PlayerControlButton(
                                    tooltip: widget.fullscreen
                                        ? l10n.animePlayerExitFullscreen
                                        : l10n.animePlayerFullscreen,
                                    icon: widget.fullscreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    iconSize: controlButtonSize,
                                    extent: controlButtonExtent,
                                    onPressed: widget.onFullscreen,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _togglePlay() {
    _showControls();
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
    setState(() {});
  }
}

class _PlayerPlaylistOverlay extends StatefulWidget {
  final List<AnimeChapter> chapters;
  final String currentChapterUuid;
  final ValueChanged<AnimeChapter> onSelected;
  final VoidCallback onClose;

  const _PlayerPlaylistOverlay({
    required this.chapters,
    required this.currentChapterUuid,
    required this.onSelected,
    required this.onClose,
  });

  @override
  State<_PlayerPlaylistOverlay> createState() => _PlayerPlaylistOverlayState();
}

class _PlayerPlaylistOverlayState extends State<_PlayerPlaylistOverlay> {
  static const _chipExtent = 40.0;
  static const _chipMaxCross = 96.0;
  static const _chipSpacing = 6.0;
  static const _headerHeight = 48.0;
  static const _panelPadding = 12.0;

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrent() {
    if (!_scrollController.hasClients) return;
    final index = widget.chapters.indexWhere(
      (c) => c.uuid == widget.currentChapterUuid,
    );
    if (index < 0) return;

    final panelWidth = _scrollController.position.viewportDimension;
    // 与 GridView 列数估算一致，保证当前集尽量进视口
    final cols = ((panelWidth + _chipSpacing) / (_chipMaxCross + _chipSpacing))
        .floor()
        .clamp(1, 6);
    final row = index ~/ cols;
    final target = row * (_chipExtent + _chipSpacing) - _chipExtent;
    _scrollController.jumpTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.42).clamp(280.0, 420.0).toDouble();
    final maxHeight = (size.height * 0.88).clamp(240.0, size.height).toDouble();

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        height: maxHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE6121212),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 24,
                offset: const Offset(-4, 0),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              children: [
                SizedBox(
                  height: _headerHeight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.playlist_play_rounded,
                          color: cs.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.animePlayerChapterSelectorWithCount(
                              widget.chapters.length,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.closeButton,
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white70,
                          iconSize: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(_panelPadding),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: _chipMaxCross,
                          mainAxisExtent: _chipExtent,
                          mainAxisSpacing: _chipSpacing,
                          crossAxisSpacing: _chipSpacing,
                        ),
                    itemCount: widget.chapters.length,
                    itemBuilder: (context, index) {
                      final chapter = widget.chapters[index];
                      final selected =
                          chapter.uuid == widget.currentChapterUuid;
                      return _PlayerPlaylistChip(
                        label: chapter.name,
                        selected: selected,
                        primary: cs.primary,
                        onPrimary: cs.onPrimary,
                        onTap: () => widget.onSelected(chapter),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerPlaylistChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color primary;
  final Color onPrimary;
  final VoidCallback onTap;

  const _PlayerPlaylistChip({
    required this.label,
    required this.selected,
    required this.primary,
    required this.onPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? primary : Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? primary
                  : Colors.white.withValues(alpha: 0.14),
              width: selected ? 1.4 : 0.8,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? onPrimary : Colors.white,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${duration.inMinutes}:$seconds';
}

class _VideoTopBar extends StatelessWidget {
  final String title;

  const _VideoTopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.backButton,
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
