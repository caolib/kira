import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../l10n/app_localizations.dart';
import '../../models/novel_reader_settings.dart';
import '../../theme/app_spacing.dart';
import '../../theme/novel_reader_theme.dart';
import '../../utils/app_logger.dart';
import '../../utils/fling_brake_tap_guard.dart';
import 'novel_reader_document.dart';
import 'novel_reader_paginator.dart' show novelPageMetricsFor;

/// Owns layout restoration, so neither initial layout nor a font/viewport change
/// can emit a spurious paragraph zero to the persistence layer.
class NovelReaderViewport extends StatefulWidget {
  const NovelReaderViewport({
    super.key,
    required this.document,
    required this.settings,
    required this.palette,
    required this.target,
    required this.jumpRevision,
    required this.onPosition,
    required this.onTap,
    this.onParagraphLongPress,
    this.highlight,
    this.highlightOpacity,
    this.onScroll,
    this.contentPadding = EdgeInsets.zero,
    this.contentRevision = 0,
    this.seam,
    this.headSeam,
    this.onApproachEnd,
    this.onReachSeam,
    this.onApproachStart,
    this.onReachStart,
  });

  final NovelTextDocument document;
  final NovelReaderSettings settings;
  final NovelReaderPalette palette;
  final NovelReaderAnchor target;
  final int jumpRevision;
  final ValueChanged<NovelReaderLocation> onPosition;
  final VoidCallback onTap;

  /// 长按段落弹出上下文菜单（与翻页模式同一手势）；回携带落点全局坐标
  /// 供菜单定位。点按仍然只切换工具栏（由外层 surface 统一处理）。
  final void Function(NovelReaderParagraph paragraph, Offset position)?
  onParagraphLongPress;

  /// 短暂高亮的书签段落（书签指向处进入/打书签成功时闪光提示）。
  /// 由阅读页持有定时清除，viewport 只按参数渲染，不改变布局。
  final NovelReaderAnchor? highlight;

  /// 高亮的淡入淡出动画：画笔挂它逐帧重绘，高亮不触发整树 rebuild。
  final Animation<double>? highlightOpacity;

  final VoidCallback? onScroll;

  /// 进入页面时快照的系统栏安全区 inset。viewport 本身铺满全屏（纸张延伸
  /// 到屏幕顶/底），这份 inset 作为列表内容的固定 padding，保证首段不被
  /// 状态栏遮挡、滚动途中不触发 viewport 尺寸变化。
  final EdgeInsets contentPadding;

  /// 正文在原位追加了新卷（item 数变多但已有内容位置不变）。与文档身份
  /// 变化区分开：追加不重定位滚动，空行显隐/换卷才重定位。
  final int contentRevision;

  /// 卷末接缝处的内容：下一卷加载中 / 加载失败 / 未下载。无下一卷时为 null。
  final Widget? seam;

  /// 卷首接缝处的内容：上一卷加载失败 / 未下载。无上一卷时为 null。
  final Widget? headSeam;

  /// 接近卷末（约两屏）时触发下一卷预取。
  final VoidCallback? onApproachEnd;

  /// 卷末最后一行距视口底部超过 10% 屏高时触发追加下一卷。
  final VoidCallback? onReachSeam;

  /// 卷首进入视口（约一屏）时触发上一卷预取。
  final VoidCallback? onApproachStart;

  /// 卷首第一段顶部进入视口后触发拼接上一卷。
  final VoidCallback? onReachStart;

  @override
  State<NovelReaderViewport> createState() => NovelReaderViewportState();
}

class NovelReaderViewportState extends State<NovelReaderViewport> {
  final _scroll = ItemScrollController();
  final _offset = ScrollOffsetController();
  final _positions = ItemPositionsListener.create();
  final _lastParagraphBodyKey = GlobalKey();
  final _headSeamKey = GlobalKey();
  late NovelReaderAnchor _desired;
  NovelReaderLocation? _lastLocation;
  Size? _size;
  TextScaler? _textScaler;
  bool _restoring = true;
  int _restoration = 0;

  /// True from a user drag start (or fling) until the gesture-driven scroll
  /// ends. Only these notifications hide the toolbar, so programmatic anchor
  /// restoration never does.
  bool _userScrolling = false;

  /// 猛滑后点一下只是给惯性刹车，这种点击不切换工具栏（与漫画阅读器一致）。
  final _flingBrakeGuard = FlingBrakeTapGuard();

  /// 卷末预取/追加的节流：同一次滑动只触发一次，直到回调方装载新内容。
  bool _approachNotified = false;
  bool _seamNotified = false;
  bool _approachStartNotified = false;
  bool _startNotified = false;

  /// 本轮是否真的由读者向下滑过。打开一卷时若内容很短，末段本来就在
  /// 触发阈值内；没有这道闸门会在开卷瞬间一路追加，把整本书都读进来。
  bool _scrolledForward = false;

  /// 本轮是否真的由读者向上回滑过。卷首拼接同样需要读者意图，
  /// 否则打开一卷时会立刻把上一卷也拼进来。
  bool _scrolledBackward = false;

  /// Null during any restoration: callers may flush their last valid snapshot,
  /// but must not replace it with a transient layout position.
  NovelReaderLocation? get currentLocation =>
      _restoring ? null : _readPosition();

  /// 视口垂直中点所覆盖段落的定位。打书签以此为参照（阅读习惯是
  /// 把内容滚到屏幕中间看，而不是以顶部首段为基准），恢复位置时
  /// 用锚点自带的 alignment 即可还原到保存时的视口位置。
  /// 中点落在空行/空章节占位上时，就近改选有文本的段落——
  /// 绝不给空行打书签。恢复过程中或无可见内容时返回 null。
  NovelReaderLocation? anchorAtViewportCenter() {
    if (_restoring || widget.document.itemCount == 0) return null;
    ItemPosition? center;
    var bestDistance = double.infinity;
    for (final item in _positions.itemPositions.value) {
      if (item.itemTrailingEdge <= 0 || item.itemLeadingEdge >= 1) continue;
      final mid = (item.itemLeadingEdge + item.itemTrailingEdge) / 2;
      final distance = (mid - 0.5).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        center = item;
      }
    }
    if (center == null) return null;
    if (_isEmptyParagraph(center.index)) {
      ItemPosition? fallback;
      var fallbackDistance = double.infinity;
      for (final item in _positions.itemPositions.value) {
        if (item.itemTrailingEdge <= 0 || item.itemLeadingEdge >= 1) continue;
        if (_isEmptyParagraph(item.index)) continue;
        final mid = (item.itemLeadingEdge + item.itemTrailingEdge) / 2;
        final distance = (mid - 0.5).abs();
        if (distance < fallbackDistance) {
          fallbackDistance = distance;
          fallback = item;
        }
      }
      // 可见项里没有正文时按目录顺序向外找（先向前）。
      center =
          fallback ??
          _nearestTextItemAway(center.index, center.itemLeadingEdge);
      if (center == null) return null;
    }
    final extent = center.itemTrailingEdge - center.itemLeadingEdge;
    final fraction = extent <= 0
        ? 0.0
        : ((0.5 - center.itemLeadingEdge) / extent).clamp(0.0, 1.0);
    return NovelReaderLocation(
      anchor: widget.document.anchorFor(
        center.index,
        alignment: _anchorAlignment(center),
      ),
      itemIndex: center.index,
      progress: widget.document.progressAt(center.index, fraction),
    );
  }

  /// 持久化用的段落前缘位置。卷首接缝提示插在首段上方，但它不属于正文：
  /// 首段已部分滚出视口时扣掉提示高度，重进页面（提示不存在）才不会
  /// 在正文里多跳过一段距离。首段顶部仍在视口内时按 0 处理（读者在卷首）。
  double _anchorAlignment(ItemPosition item) {
    final leading = item.itemLeadingEdge;
    if (item.index != 0 || leading >= 0 || widget.headSeam == null) {
      return leading;
    }
    final seam = _headSeamKey.currentContext?.findRenderObject();
    final height = _size?.height ?? 0;
    if (seam is! RenderBox || !seam.hasSize || height <= 0) return leading;
    return leading + seam.size.height / height;
  }

  bool _isEmptyParagraph(int index) =>
      widget.document.paragraphAt(index).text.trim().isEmpty;

  /// 从 [from] 按目录顺序向外（先向前）找最近的有文本段落，
  /// 返回合成的 ItemPosition（视口位置用 [leadingEdge] 近似）。
  ItemPosition? _nearestTextItemAway(int from, double leadingEdge) {
    final count = widget.document.itemCount;
    for (var distance = 1; distance < count; distance++) {
      final previous = from - distance;
      if (previous >= 0 && !_isEmptyParagraph(previous)) {
        return ItemPosition(
          index: previous,
          itemLeadingEdge: leadingEdge,
          itemTrailingEdge: leadingEdge + 1,
        );
      }
      final next = from + distance;
      if (next < count && !_isEmptyParagraph(next)) {
        return ItemPosition(
          index: next,
          itemLeadingEdge: leadingEdge,
          itemTrailingEdge: leadingEdge + 1,
        );
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _desired = widget.target;
    _positions.itemPositions.addListener(_onPositions);
    _scheduleRestore(_desired);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scaler = MediaQuery.textScalerOf(context);
    if (_textScaler != null && _textScaler != scaler) {
      _scheduleRestore(
        _restoring ? _desired : _lastLocation?.anchor ?? _desired,
      );
    }
    _textScaler = scaler;
  }

  @override
  void didUpdateWidget(NovelReaderViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentRevision != widget.contentRevision) {
      // 连续阅读在原位追加了下一卷（或拼接了上一卷）：已有内容位置不变，
      // 只解锁接缝节流，让读者能继续滑到新的卷首/卷末。不重定位滚动，
      // 否则视口会跳。
      _rearmSeam();
      // 回收旧卷会改变 item 下标，此时 jumpRevision 同步递增，走下面的
      // 重定位分支；单纯追加则到此为止。
      if (oldWidget.jumpRevision == widget.jumpRevision) return;
    }
    if (!identical(oldWidget.document, widget.document)) {
      // 文档重建（空行显隐切换）：列表项数与内容都变了，按目标锚点重新
      // 挂载定位；不能沿用旧 offset，恢复流程与字体变化同一套。
      _scheduleRestore(widget.target);
    } else if (oldWidget.jumpRevision != widget.jumpRevision) {
      _scheduleRestore(widget.target);
    } else if (oldWidget.settings.fontSize != widget.settings.fontSize ||
        oldWidget.settings.lineHeight != widget.settings.lineHeight ||
        oldWidget.settings.paragraphSpacing !=
            widget.settings.paragraphSpacing ||
        oldWidget.settings.contentWidth != widget.settings.contentWidth) {
      _scheduleRestore(
        _restoring ? _desired : _lastLocation?.anchor ?? _desired,
      );
    }
  }

  void _scheduleRestore(NovelReaderAnchor anchor) {
    _desired = anchor;
    _restoring = true;
    // 换卷/跳转后重新要求一次真实的向下滑动，卷末判定才恢复生效。
    _rearmSeam();
    final generation = ++_restoration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_restore(generation));
    });
  }

  bool _isCurrent(int generation) => mounted && generation == _restoration;

  Future<void> _restore(int generation) async {
    if (!_isCurrent(generation) || !_scroll.isAttached) return;
    final index = widget.document.itemFor(_desired);
    final alignment = _desired.alignment.isFinite ? _desired.alignment : 0.0;
    try {
      // PositionedList uses alignment as a viewport anchor and asserts [0, 1].
      // Never pass a saved negative leading edge to initialAlignment/jumpTo.
      _scroll.jumpTo(index: index, alignment: alignment.clamp(0.0, 0.99));
      await WidgetsBinding.instance.endOfFrame;
      if (!_isCurrent(generation)) return;
      if (alignment < 0) {
        final target = _positions.itemPositions.value
            .where((item) => item.index == index)
            .firstOrNull;
        final height = _size?.height ?? 0;
        if (target == null || height <= 0) return;
        // Corrupt/stale offsets (or shorter text after reflow) must not jump
        // into a different paragraph. Keep at least one pixel of this one.
        final extent = target.itemTrailingEdge - target.itemLeadingEdge;
        final inside = math.min(
          -alignment * height,
          math.max(0.0, extent * height - 1),
        );
        if (inside > 0) {
          await _offset.animateScroll(
            offset: inside,
            duration: const Duration(milliseconds: 1),
          );
          if (!_isCurrent(generation)) return;
          await WidgetsBinding.instance.endOfFrame;
        }
      }
      if (!_isCurrent(generation)) return;
      setState(() => _restoring = false);
      _onPositions();
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'novel_reader.restore',
        ),
      );
    }
  }

  NovelReaderLocation? _readPosition() {
    final visible = _positions.itemPositions.value.where(
      (item) => item.itemTrailingEdge > 0.001 && item.itemLeadingEdge < 1,
    );
    ItemPosition? first;
    for (final item in visible) {
      if (first == null || item.index < first.index) first = item;
    }
    if (first == null || first.index >= widget.document.itemCount) return null;
    final extent = first.itemTrailingEdge - first.itemLeadingEdge;
    final fraction = extent <= 0
        ? 0.0
        : (-first.itemLeadingEdge / extent).clamp(0.0, 1.0);
    return NovelReaderLocation(
      anchor: widget.document.anchorFor(
        first.index,
        alignment: _anchorAlignment(first),
      ),
      itemIndex: first.index,
      progress:
          first.index == widget.document.itemCount - 1 &&
              first.itemTrailingEdge <= 1.001
          ? 1
          : widget.document.progressAt(first.index, fraction),
    );
  }

  void _onPositions() {
    if (!mounted || _restoring) return;
    _checkVolumeSeam();
    final location = _readPosition();
    if (location == null) return;
    _lastLocation = location;
    widget.onPosition(location);
  }

  /// 卷末接缝判定：末段接近两屏时预取，正文实际下沿距底部超过 10% 屏高时追加。
  /// 末段有至少一屏的占位留白，不能用它的 item 边界代替正文末行。
  ///
  /// 卷首对称：首段进入视口即预取上一卷；首段顶部回到视口内（读者已在卷首）
  /// 时拼接上一卷。两者都要求本轮发生过真实的向上滚动。
  void _checkVolumeSeam() {
    _checkVolumeEnd();
    _checkVolumeStart();
  }

  void _checkVolumeEnd() {
    if (!_scrolledForward) return;
    if (widget.onApproachEnd == null && widget.onReachSeam == null) return;
    final lastIndex = widget.document.itemCount - 1;
    if (lastIndex < 0) return;
    ItemPosition? last;
    for (final item in _positions.itemPositions.value) {
      if (item.index == lastIndex) last = item;
    }
    if (last == null) return;
    if (!_approachNotified && last.itemLeadingEdge <= 2) {
      _approachNotified = true;
      widget.onApproachEnd?.call();
    }
    if (_seamNotified) return;
    final body = _lastParagraphBodyKey.currentContext?.findRenderObject();
    final viewport = context.findRenderObject();
    if (body is! RenderBox || viewport is! RenderBox || !body.hasSize) return;
    final bottom = body
        .localToGlobal(Offset(0, body.size.height), ancestor: viewport)
        .dy;
    if (bottom < viewport.size.height * 0.9) {
      _seamNotified = true;
      widget.onReachSeam?.call();
    }
  }

  void _checkVolumeStart() {
    if (!_scrolledBackward) return;
    if (widget.onApproachStart == null && widget.onReachStart == null) return;
    ItemPosition? first;
    for (final item in _positions.itemPositions.value) {
      if (item.index == 0) {
        first = item;
        break;
      }
    }
    if (first == null) return;
    final visible = first.itemLeadingEdge < 1 && first.itemTrailingEdge > 0;
    if (!visible) return;
    if (!_approachStartNotified) {
      _approachStartNotified = true;
      widget.onApproachStart?.call();
    }
    if (_startNotified) return;
    // 首段顶部在视口内：卷首之上只剩系统栏留白，继续回滑就是上一卷。
    if (first.itemLeadingEdge >= -0.001) {
      _startNotified = true;
      widget.onReachStart?.call();
    }
  }

  /// 追加/拼接新卷后重新解锁接缝：只有读者继续同向滑动才会再次触发，
  /// 避免一帧内连跳多卷。
  void _rearmSeam() {
    _approachNotified = false;
    _seamNotified = false;
    _approachStartNotified = false;
    _startNotified = false;
    _scrolledForward = false;
    _scrolledBackward = false;
  }

  /// 页面层因反方向拼接正在进行而放弃本次接缝触发时调用：重新解锁，
  /// 读者继续滑动即可重试，而不会永久丢掉这次触发机会。
  void rearmSeams() => _rearmSeam();

  @override
  void dispose() {
    ++_restoration;
    _positions.itemPositions.removeListener(_onPositions);
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (_restoring) {
      _userScrolling = false;
      return false;
    }
    // 喂给刹车守卫：区分「手指仍按着拖」与「抬手后的惯性」，供点击刹车判定
    // 使用。程序化 restore 已在上面提前返回，不会污染记录。
    if (notification is ScrollUpdateNotification &&
        (notification.scrollDelta ?? 0) != 0) {
      _flingBrakeGuard.recordScroll(
        isDrag: notification.dragDetails != null,
        at: DateTime.now(),
      );
      // 只有读者真正向下滑过，卷末接缝判定才生效；反方向同理用于卷首。
      if ((notification.scrollDelta ?? 0) > 0) _scrolledForward = true;
      if ((notification.scrollDelta ?? 0) < 0) _scrolledBackward = true;
    }
    // 正文恰好一屏（或末段被撑满一屏）时无法产生滚动位移，向下越界也算
    // 读者在继续下滑：此时接缝判定已经成立，直接补一次。
    if (notification is OverscrollNotification && notification.overscroll > 0) {
      _scrolledForward = true;
      _checkVolumeSeam();
    }
    if (notification is OverscrollNotification && notification.overscroll < 0) {
      _scrolledBackward = true;
      _checkVolumeSeam();
    }
    // A user session opens at any ScrollStart (drag or the ballistic phase
    // after finger release) or an explicit direction change, but only an
    // actual ScrollUpdate hides the toolbar: a programmatic jumpTo also
    // emits a Start/End pair without updates, and must not hide anything.
    // Because the session stays open through the ballistic update stream,
    // a toolbar expanded mid-inertia hides again on the next update.
    if (notification is ScrollStartNotification ||
        (notification is UserScrollNotification &&
            notification.direction != ScrollDirection.idle)) {
      _userScrolling = true;
    } else if (notification is ScrollUpdateNotification && _userScrolling) {
      widget.onScroll?.call();
    } else if (notification is ScrollEndNotification) {
      _userScrolling = false;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (_size != null && _size != size) {
          _scheduleRestore(
            _restoring ? _desired : _lastLocation?.anchor ?? _desired,
          );
        }
        _size = size;
        return Listener(
          // 按下的瞬间列表若还在惯性滚动，这次触摸只是刹车（见
          // FlingBrakeTapGuard）。判定放在 pointer-down 而不是 onTap 里。
          onPointerDown: (_) => _flingBrakeGuard.onPointerDown(DateTime.now()),
          child: AbsorbPointer(
            absorbing: _restoring,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: GestureDetector(
                key: const ValueKey('novel-reader-surface'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (_flingBrakeGuard.consumeTap()) return;
                  widget.onTap();
                },
                child: ScrollablePositionedList.builder(
                  key: const ValueKey('novel-reader-paragraphs'),
                  itemCount: widget.document.itemCount,
                  itemScrollController: _scroll,
                  scrollOffsetController: _offset,
                  itemPositionsListener: _positions,
                  initialScrollIndex: widget.document.itemFor(_desired),
                  initialAlignment: _desired.alignment.isFinite
                      ? _desired.alignment.clamp(0.0, 0.99)
                      : 0,
                  addAutomaticKeepAlives: false,
                  // 横向与分页共用限宽；纵向用快照 inset 避开系统栏。
                  padding: () {
                    final metrics = novelPageMetricsFor(
                      size,
                      widget.contentPadding,
                      maxContentWidth: widget.settings.contentWidth,
                    );
                    return EdgeInsets.fromLTRB(
                      widget.contentPadding.left + metrics.horizontalPadding,
                      widget.contentPadding.top,
                      widget.contentPadding.right + metrics.horizontalPadding,
                      widget.contentPadding.bottom,
                    );
                  }(),
                  itemBuilder: _buildParagraph,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildParagraph(BuildContext context, int index) {
    final paragraph = widget.document.paragraphAt(index);
    final entry = paragraph.entry;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final foreground = widget.palette.foreground;
    final style = tt.bodyLarge!.copyWith(
      color: foreground,
      fontSize: widget.settings.fontSize,
      height: widget.settings.lineHeight,
    );
    final highlighted =
        widget.highlight != null &&
        widget.highlight!.entryIndex == entry.entryIndex &&
        widget.highlight!.paragraphIndex == paragraph.paragraphIndex &&
        (widget.highlight!.volumeId.isEmpty ||
            widget.highlight!.volumeId ==
                widget.document.volumeIdForItem(index));
    final bodyText = entry.paragraphs.isEmpty
        ? l10n.novelReaderEmptyChapter
        : (paragraph.text.isEmpty ? ' ' : paragraph.text);
    Widget body = Text(bodyText, style: style);
    // 高亮样式由演示切换器实时决定；DecoratedBox 不参与布局，高亮
    // 出现/消失时正文一个像素都不动，锚点与进度不受闪光影响。
    // 高亮卡片画在段落矩形之外的留白里（不参与布局），出现/消失正文
    // 零位移；透明度由页面持有的动画驱动，逐帧重绘不重建子树。
    if (highlighted) {
      body = CustomPaint(
        painter: NovelHighlightPainter(
          color: widget.palette.foreground,
          fontSize: widget.settings.fontSize,
          opacity: widget.highlightOpacity,
        ),
        child: body,
      );
    }
    if (widget.onParagraphLongPress != null) {
      body = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: (details) =>
            widget.onParagraphLongPress!(paragraph, details.globalPosition),
        child: body,
      );
    }
    if (index == widget.document.itemCount - 1) {
      body = KeyedSubtree(key: _lastParagraphBodyKey, child: body);
    }
    final child = Padding(
      key: ValueKey(
        'novel-paragraph-${entry.entryIndex}-${paragraph.paragraphIndex}',
      ),
      // 长末段也留出足够的卷末滚动空间，让正文下沿能越过底部 10% 阈值。
      padding: EdgeInsets.only(
        bottom:
            widget.settings.paragraphSpacing +
            (index == widget.document.itemCount - 1 &&
                    widget.onReachSeam != null
                ? (_size?.height ?? 0) * 0.1 + AppSpacing.xs
                : 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (index == 0 && widget.headSeam != null)
            KeyedSubtree(key: _headSeamKey, child: widget.headSeam!),
          if (paragraph.paragraphIndex == 0 && entry.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Text(
                entry.name,
                style: tt.headlineSmall?.copyWith(color: foreground),
              ),
            ),
          // An empty source line is a real paragraph, not something to trim.
          body,
        ],
      ),
    );
    // Leave room to put even a short final paragraph at the top. Without it,
    // the list clamps a jump near EOF backwards into the preceding chapter or
    // illustration, and the next saved anchor would silently be wrong.
    // 卷末接缝提示紧贴最后一段之后，不额外占 item 下标。
    return index == widget.document.itemCount - 1
        ? ConstrainedBox(
            constraints: BoxConstraints(minHeight: _size?.height ?? 0),
            child: widget.seam == null
                ? child
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [child, widget.seam!],
                  ),
          )
        : child;
  }
}
