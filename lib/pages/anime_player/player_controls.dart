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

class _VideoPlayerSurface extends StatefulWidget {
  final VideoController controller;
  final bool fullscreen;
  final VoidCallback onSkipForward;
  final VoidCallback onSettings;
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
    required this.onSettings,
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
    const controlButtonSize = 24.0;
    const controlButtonExtent = 40.0;

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
                        unawaited(AppLogger.instance.recordWarning(
                          e,
                          stackTrace: stack,
                          source: 'player_controls.set_brightness',
                        ));
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
              if (_playlistVisible)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _hidePlaylist,
                    child: Align(
                      alignment: widget.fullscreen
                          ? Alignment.centerRight
                          : Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: widget.fullscreen ? 32 : 8,
                          right: widget.fullscreen ? 56 : 8,
                          bottom: widget.fullscreen ? 64 : 48,
                        ),
                        child: _PlayerPlaylistOverlay(
                          chapters: widget.chapters,
                          currentChapterUuid: widget.currentChapterUuid,
                          onSelected: (chapter) {
                            _hidePlaylist();
                            widget.onChapterSelected(chapter);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.fullscreen)
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
                            padding: const EdgeInsets.fromLTRB(4, 8, 16, 16),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: '退出全屏',
                                  onPressed: widget.onFullscreen,
                                  icon: const Icon(Icons.arrow_back),
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
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
                                  SizedBox(
                                    width: widget.fullscreen ? 132 : 104,
                                    child: Text(
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
                                  ),
                                  Expanded(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      reverse: true,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _PlayerControlButton(
                                            tooltip: playing ? '暂停' : '播放',
                                            icon: playing
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: _togglePlay,
                                          ),
                                          _PlayerControlButton(
                                            tooltip:
                                                '快进 ${UserManager().animeSkipSeconds}秒',
                                            icon: Icons.fast_forward,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: widget.onSkipForward,
                                          ),
                                          _PlayerControlButton(
                                            tooltip: widget.danmakuVisible
                                                ? '隐藏弹幕'
                                                : '显示弹幕',
                                            icon: widget.danmakuVisible
                                                ? Icons.subtitles
                                                : Icons.subtitles_off,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: widget.onToggleDanmaku,
                                          ),
                                          _PlayerControlButton(
                                            tooltip: '选集',
                                            icon: Icons.playlist_play,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: _togglePlaylist,
                                          ),
                                          _PlayerControlButton(
                                            tooltip: '设置跳转秒数',
                                            icon: Icons.settings,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: widget.onSettings,
                                          ),
                                          _PlayerControlButton(
                                            tooltip: widget.fullscreen
                                                ? '退出全屏'
                                                : '全屏',
                                            icon: widget.fullscreen
                                                ? Icons.fullscreen_exit
                                                : Icons.fullscreen,
                                            iconSize: controlButtonSize,
                                            extent: controlButtonExtent,
                                            onPressed: widget.onFullscreen,
                                          ),
                                        ],
                                      ),
                                    ),
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

class _PlayerPlaylistOverlay extends StatelessWidget {
  final List<AnimeChapter> chapters;
  final String currentChapterUuid;
  final ValueChanged<AnimeChapter> onSelected;

  const _PlayerPlaylistOverlay({
    required this.chapters,
    required this.currentChapterUuid,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const itemTextStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.2,
    );
    final maxWidth = (size.width * 0.34).clamp(240.0, 340.0).toDouble();
    final textMaxWidth = maxWidth - 56;
    var widestTitle = 0.0;
    for (final chapter in chapters) {
      final painter = TextPainter(
        text: TextSpan(text: chapter.name, style: itemTextStyle),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: textMaxWidth);
      if (painter.width > widestTitle) widestTitle = painter.width;
    }
    final width = (widestTitle + 44).clamp(200.0, maxWidth).toDouble();
    final maxHeight = (size.height * 0.78).clamp(220.0, 620.0).toDouble();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: chapters.length,
              itemBuilder: (context, index) {
                final chapter = chapters[index];
                final selected = chapter.uuid == currentChapterUuid;
                return _PlayerPlaylistItem(
                  chapter: chapter,
                  selected: selected,
                  textStyle: itemTextStyle,
                  onTap: () => onSelected(chapter),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerPlaylistItem extends StatelessWidget {
  final AnimeChapter chapter;
  final bool selected;
  final TextStyle textStyle;
  final VoidCallback onTap;

  const _PlayerPlaylistItem({
    required this.chapter,
    required this.selected,
    required this.textStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF03A9F4) : Colors.white;

    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  chapter.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle.copyWith(color: color),
                ),
              ),
            ],
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
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
