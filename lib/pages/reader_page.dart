import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../api/api_client.dart';
import '../models/chapter.dart';
import '../models/user_manager.dart';
import '../utils/toast.dart';

class ReaderPage extends StatefulWidget {
  final String pathWord;
  final String chapterUuid;
  final String chapterName;

  const ReaderPage({
    super.key,
    required this.pathWord,
    required this.chapterUuid,
    required this.chapterName,
  });

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  static const _volumeChannel = MethodChannel('com.example.kira/volume');

  final _api = ApiClient();
  final _user = UserManager();
  final _scrollController = ScrollController();
  PageController _pageController = PageController();
  ChapterDetail? _detail;
  bool _loading = true;
  bool _showToolbar = false;
  late String _currentUuid;
  int _currentPage = 1;
  bool _jumpingScroll = false;
  bool _isDraggingSlider = false;

  bool get _isPageMode => _user.readerMode == 1;
  bool get _isDarkMode =>
      Theme.of(context).brightness == Brightness.dark;

  @override
  void initState() {
    super.initState();
    _currentUuid = widget.chapterUuid;
    _loadChapter();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _volumeChannel.setMethodCallHandler(_handleVolumeMethod);
    _updateVolumeIntercept();
  }

  @override
  void dispose() {
    _volumeChannel.invokeMethod('disable');
    _volumeChannel.setMethodCallHandler(null);
    _scrollController.dispose();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<dynamic> _handleVolumeMethod(MethodCall call) async {
    if (!_user.readerVolumeKey || !_isPageMode || _detail == null) return;
    if (call.method == 'volumeUp') _prevPage();
    if (call.method == 'volumeDown') _nextPage();
  }

  void _updateVolumeIntercept() {
    final should = _isPageMode && _user.readerVolumeKey;
    _volumeChannel.invokeMethod(should ? 'enable' : 'disable');
  }

  Future<void> _loadChapter() async {
    setState(() => _loading = true);
    try {
      final detail =
          await _api.getChapterDetail(widget.pathWord, _currentUuid);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _currentPage = 1;
      });
      if (_isPageMode) {
        _pageController.dispose();
        _pageController = PageController();
      } else {
        _scrollController.jumpTo(0);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goChapter(String? uuid) {
    if (uuid == null) return;
    _currentUuid = uuid;
    _loadChapter();
  }

  void _prevPage() {
    if (_detail == null) return;
    if (_currentPage > 1) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (_detail!.prev != null) {
      _goChapter(_detail!.prev);
    } else {
      showToast(context, '已经是第一页了');
    }
  }

  void _nextPage() {
    if (_detail == null) return;
    if (_currentPage < _detail!.contents.length) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else if (_detail!.next != null) {
      _goChapter(_detail!.next);
    } else {
      showToast(context, '已经是最后一页了');
    }
  }

  void _onSettingsChanged() {
    final page = _currentPage;
    _updateVolumeIntercept();
    setState(() {});
    if (_isPageMode) {
      _pageController.dispose();
      _pageController = PageController(initialPage: page - 1);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients &&
            _detail != null &&
            _detail!.contents.isNotEmpty) {
          final ratio = (page - 1) / _detail!.contents.length;
          _jumpingScroll = true;
          _scrollController
              .jumpTo(ratio * _scrollController.position.maxScrollExtent);
          _jumpingScroll = false;
        }
      });
    }
  }

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReaderSettingsPanel(
        onChanged: _onSettingsChanged,
      ),
    );
  }

  // ── 公共图片组件 ──

  Widget _buildImage(int index) {
    final cs = Theme.of(context).colorScheme;
    Widget image = CachedNetworkImage(
      imageUrl: _detail!.contents[index],
      fit: _isPageMode ? BoxFit.contain : BoxFit.fitWidth,
      width: double.infinity,
      placeholder: (_, _) => Container(
        height: 400,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (_, _, _) => Container(
        height: 400,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image, color: cs.onSurfaceVariant, size: 48),
              const SizedBox(height: 8),
              Text('加载失败',
                  style:
                      TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
    // 深色模式亮度遮罩
    if (_isDarkMode && _user.readerDimming > 0) {
      image = Stack(
        children: [
          image,
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: _user.readerDimming),
              ),
            ),
          ),
        ],
      );
    }
    return image;
  }

  // ── 滚动模式 ──

  Widget _buildScrollMode() {
    final imageCount = _detail!.contents.length;
    final hasHeader = _detail!.prev == null;
    final totalItems = (hasHeader ? 1 : 0) + imageCount + 1;
    return GestureDetector(
      onTap: () => setState(() => _showToolbar = !_showToolbar),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (_jumpingScroll || _isDraggingSlider) return false;
          if (n is ScrollUpdateNotification &&
              _showToolbar &&
              (n.scrollDelta ?? 0).abs() > 0) {
            setState(() => _showToolbar = false);
          }
          if (n.metrics.pixels > 0 && n.metrics.maxScrollExtent > 0) {
            final page = (imageCount * n.metrics.pixels /
                    n.metrics.maxScrollExtent)
                .ceil()
                .clamp(1, imageCount);
            if (page != _currentPage) {
              setState(() => _currentPage = page);
            }
          }
          return false;
        },
        child: ListView.separated(
          controller: _scrollController,
          itemCount: totalItems,
          separatorBuilder: (_, i) {
            final imageStart = hasHeader ? 1 : 0;
            final imageEnd = imageStart + imageCount - 1;
            if (i >= imageStart && i < imageEnd) {
              return SizedBox(height: _user.readerImageGap);
            }
            return const SizedBox.shrink();
          },
          itemBuilder: (_, i) {
            if (hasHeader && i == 0) return _buildFirstChapterHead();
            final imageIndex = i - (hasHeader ? 1 : 0);
            if (imageIndex < imageCount) return _buildImage(imageIndex);
            return _buildNextChapterTail();
          },
        ),
      ),
    );
  }

  Widget _buildFirstChapterHead() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: Text('已经是第一章',
            style: TextStyle(color: Colors.white54, fontSize: 14)),
      ),
    );
  }

  Widget _buildNextChapterTail() {
    final hasNext = _detail?.next != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Center(
        child: FilledButton.icon(
          onPressed: hasNext
              ? () => _goChapter(_detail!.next)
              : () => Navigator.pop(context),
          icon: Icon(hasNext ? Icons.skip_next : Icons.list),
          label: Text(hasNext ? '下一章' : '返回目录'),
        ),
      ),
    );
  }

  // ── 翻页模式 ──

  Widget _buildPageMode() {
    return GestureDetector(
      onTapUp: (details) {
        final screenWidth = MediaQuery.of(context).size.width;
        final x = details.globalPosition.dx;
        if (x < screenWidth / 3) {
          _user.readerPageRTL ? _nextPage() : _prevPage();
        } else if (x > screenWidth * 2 / 3) {
          _user.readerPageRTL ? _prevPage() : _nextPage();
        } else {
          setState(() => _showToolbar = !_showToolbar);
        }
      },
      child: PageView.builder(
        controller: _pageController,
        reverse: _user.readerPageRTL,
        allowImplicitScrolling: true,
        itemCount: _detail!.contents.length,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index + 1;
            if (!_isDraggingSlider) _showToolbar = false;
          });
        },
        itemBuilder: (_, i) => Center(child: _buildImage(i)),
      ),
    );
  }

  // ── 工具栏 ──

  Widget _buildTopBar() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      top: _showToolbar ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.85),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    _detail?.name ?? widget.chapterName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    final total = _detail!.contents.length;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      bottom: _showToolbar ? 0 : -100,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.85),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 滚动条 Slider
                Row(
                  children: [
                    Text('$_currentPage',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7),
                          activeTrackColor: cs.primary,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: cs.primary,
                          overlayColor: cs.primary.withValues(alpha: 0.2),
                        ),
                        child: Slider(
                          value: _currentPage.toDouble(),
                          min: 1,
                          max: total.toDouble(),
                          onChangeStart: (_) {
                            _isDraggingSlider = true;
                            _jumpingScroll = true;
                          },
                          onChangeEnd: (_) {
                            _isDraggingSlider = false;
                            // 延迟恢复，避免 jumpTo 后的惯性通知隐藏工具栏
                            Future.delayed(
                              const Duration(milliseconds: 100),
                              () => _jumpingScroll = false,
                            );
                          },
                          onChanged: (v) {
                            final page = v.round();
                            setState(() => _currentPage = page);
                            if (_isPageMode) {
                              _pageController.jumpToPage(page - 1);
                            } else if (_scrollController.hasClients) {
                              final ratio = (page - 1) / total;
                              _scrollController.jumpTo(ratio *
                                  _scrollController
                                      .position.maxScrollExtent);
                            }
                          },
                        ),
                      ),
                    ),
                    Text('$total',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ],
                ),
                // 按钮行
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _detail!.prev != null
                          ? () => _goChapter(_detail!.prev)
                          : null,
                      icon: const Icon(Icons.chevron_left),
                      label: const Text('上一章'),
                      style: TextButton.styleFrom(
                        foregroundColor: _detail!.prev != null
                            ? Colors.white
                            : Colors.white38,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.settings, color: Colors.white),
                      onPressed: _showSettingsPanel,
                      tooltip: '阅读设置',
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _detail!.next != null
                          ? () => _goChapter(_detail!.next)
                          : null,
                      icon: const Text('下一章'),
                      label: const Icon(Icons.chevron_right),
                      style: TextButton.styleFrom(
                        foregroundColor: _detail!.next != null
                            ? Colors.white
                            : Colors.white38,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_detail != null)
            _isPageMode ? _buildPageMode() : _buildScrollMode(),
          _buildTopBar(),
          if (_detail != null) _buildBottomBar(cs),
        ],
      ),
    );
  }
}

// ── 设置面板 ──

class _ReaderSettingsPanel extends StatefulWidget {
  final VoidCallback onChanged;
  const _ReaderSettingsPanel({required this.onChanged});

  @override
  State<_ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

class _ReaderSettingsPanelState extends State<_ReaderSettingsPanel> {
  final _user = UserManager();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isPageMode = _user.readerMode == 1;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('阅读设置',
                  style: tt.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              // 阅读模式
              Text('阅读模式', style: tt.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.view_day),
                      label: Text('滚动'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.auto_stories),
                      label: Text('翻页'),
                    ),
                  ],
                  selected: {_user.readerMode},
                  onSelectionChanged: (v) {
                    _user.setReaderMode(v.first);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(height: 16),
              // 图片间距（仅滚动模式）
              if (!isPageMode) ...[
                Row(
                  children: [
                    Text('图片间距', style: tt.bodyMedium),
                    const Spacer(),
                    Text('${_user.readerImageGap.round()} px',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
                Slider(
                  value: _user.readerImageGap,
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (v) {
                    _user.setReaderImageGap(v);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ],
              // 翻页方向（仅翻页模式）
              if (isPageMode) ...[
                Text('翻页方向', style: tt.bodyMedium),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.arrow_forward),
                        label: Text('从左到右'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.arrow_back),
                        label: Text('从右到左'),
                      ),
                    ],
                    selected: {_user.readerPageRTL},
                    onSelectionChanged: (v) {
                      _user.setReaderPageRTL(v.first);
                      setState(() {});
                      widget.onChanged();
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // 音量键翻页
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('音量键翻页'),
                  subtitle: const Text('音量+上一页，音量-下一页'),
                  value: _user.readerVolumeKey,
                  onChanged: (v) {
                    _user.setReaderVolumeKey(v);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ],
              // 亮度遮罩（仅深色模式）
              if (isDark) ...[
                Row(
                  children: [
                    const Icon(Icons.brightness_low, size: 18),
                    const SizedBox(width: 8),
                    Text('降低亮度', style: tt.bodyMedium),
                    const Spacer(),
                    Text('${(_user.readerDimming * 100).round()}%',
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
                Slider(
                  value: _user.readerDimming,
                  min: 0,
                  max: 0.7,
                  divisions: 14,
                  onChanged: (v) {
                    _user.setReaderDimming(v);
                    setState(() {});
                    widget.onChanged();
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
