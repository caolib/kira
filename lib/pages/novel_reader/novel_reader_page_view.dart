import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';

import '../../models/novel_reader_settings.dart';
import '../../theme/app_spacing.dart';
import '../../theme/novel_reader_theme.dart';
import '../../widgets/novel_page_curl.dart';
import 'novel_reader_dialogue.dart';
import 'novel_reader_document.dart';
import 'novel_reader_font.dart';
import 'novel_reader_paginator.dart';

/// 整页翻页视图：把整卷正文按可用区域切分成页，横向左到右翻页。
///
/// 与滚动视口（[NovelReaderViewport]）对齐的语义：
/// - 恢复完成前 [currentLocation] 返回 null，程序化跳转不触发工具栏隐藏；
/// - 锚点沿用 entryIndex + paragraphIndex + alignment（负值表示段内位置），
///   进度与滚动模式同一算法，模式切换时百分比连续。
class NovelReaderPageView extends StatefulWidget {
  const NovelReaderPageView({
    super.key,
    required this.document,
    required this.settings,
    required this.palette,
    required this.target,
    required this.jumpRevision,
    required this.emptyChapterText,
    required this.contentPadding,
    required this.onPosition,
    required this.toolbarVisible,
    required this.onTap,
    this.onParagraphLongPress,
    this.highlight,
    this.highlightOpacity,
    this.onPageTurned,
    this.onBoundary,
    this.fontFamily,
  });

  final NovelTextDocument document;
  final NovelReaderSettings settings;
  final String? fontFamily;
  final NovelReaderPalette palette;

  /// 目标锚点；[jumpRevision] 变化时按同一锚点重新定位。
  final NovelReaderAnchor target;
  final int jumpRevision;
  final String emptyChapterText;
  final EdgeInsets contentPadding;
  final ValueChanged<NovelReaderLocation> onPosition;

  /// 工具栏显示时，正文点击只切换工具栏，不触发分区翻页。
  final bool toolbarVisible;

  /// 工具栏显示时点击任意区域，或隐藏时点击中间区域（切换工具栏）。
  final VoidCallback onTap;

  /// 长按段落（复制/书签菜单）；回携带落点全局坐标供菜单定位。
  final void Function(NovelReaderParagraph paragraph, Offset position)?
  onParagraphLongPress;

  /// 短暂高亮的书签段落。
  final NovelReaderAnchor? highlight;

  /// 高亮的淡入淡出动画：画笔挂它逐帧重绘，高亮不触发整树 rebuild。
  final Animation<double>? highlightOpacity;

  /// 用户翻页（非程序化）：隐藏工具栏、清除高亮。
  final VoidCallback? onPageTurned;

  /// 越过卷首/卷末继续翻页；由宿主决定加载相邻卷或提示。
  final void Function(bool forward)? onBoundary;

  @override
  State<NovelReaderPageView> createState() => NovelReaderPageViewState();
}

class NovelReaderPageViewState extends State<NovelReaderPageView>
    with SingleTickerProviderStateMixin {
  static const _turnDuration = Duration(milliseconds: 360);
  late final AnimationController _turnController;
  NovelReaderPaginator? _paginator;
  int _currentPage = 0;
  bool _restoring = true;
  bool _paginationPending = false;
  NovelReaderAnchor? _pendingAnchor;
  int _generation = 0;
  Size? _size;
  EdgeInsets? _contentPadding;
  TextScaler? _textScaler;
  NovelDialoguePresentation? _dialogue;
  TextStyle? _layoutBodyStyle;
  TextStyle? _layoutTitleStyle;

  bool _updateTextStyles() {
    final body = _bodyStyle(context);
    final title = _titleStyle(context);
    final changed =
        _layoutBodyStyle?.compareTo(body) == RenderComparison.layout ||
        _layoutTitleStyle?.compareTo(title) == RenderComparison.layout;
    _layoutBodyStyle = body;
    _layoutTitleStyle = title;
    return changed;
  }

  bool _updateDialogue() {
    final previous = _dialogue?.layoutKey;
    _dialogue = resolveNovelDialoguePresentation(
      widget.settings,
      dark: MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      foreground: widget.palette.foreground,
      background: widget.palette.background,
    );
    return previous != _dialogue?.layoutKey;
  }

  Timer? _buildTimer;
  NovelReaderLocation? _lastLocation;
  int? _turnTarget;
  bool _turnForward = true;
  bool _turnWillCommit = false;
  int _turnSerial = 0;
  int? _dragTurnSerial;
  double _turnOriginY = 0.75;
  double _dragDelta = 0;
  double _dragOriginY = 0.75;
  bool _dragCommitted = false;
  bool _dragBlocked = false;

  /// 本次拖动越过了卷首/卷末（没有可翻的页面），松手时按卷界处理。
  bool _dragOutOfBounds = false;
  bool _dragForward = true;

  /// Null during any restoration: callers may flush their last valid snapshot,
  /// but must not replace it with a transient page position.
  NovelReaderLocation? get currentLocation {
    if (_restoring) return null;
    return _locationForPage(_currentPage) ?? _lastLocation;
  }

  /// 视口垂直中点所在页的最近有正文段落（打书签以此为参照）。
  NovelReaderLocation? anchorAtViewportCenter() {
    if (_restoring) return null;
    final paragraph = _paginator?.centerParagraph(_currentPage);
    if (paragraph == null) return null;
    final anchor = NovelReaderAnchor(
      entryIndex: paragraph.entry.entryIndex,
      paragraphIndex: paragraph.paragraphIndex,
      volumeId: paragraph.volumeId,
    );
    final item = widget.document.itemFor(anchor);
    return NovelReaderLocation(
      anchor: anchor,
      itemIndex: item,
      progress: (item / widget.document.itemCount).clamp(0.0, 1.0),
    );
  }

  void nextPage() => _turn(forward: true);

  void prevPage() => _turn(forward: false);

  @override
  void initState() {
    super.initState();
    _turnController = AnimationController(vsync: this, duration: _turnDuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scaler = MediaQuery.textScalerOf(context);
    final dialogueLayoutChanged = _updateDialogue();
    final textLayoutChanged = _updateTextStyles();
    if (_textScaler != null &&
        (_textScaler != scaler || dialogueLayoutChanged || textLayoutChanged)) {
      _restart(_anchorNow());
    }
    _textScaler = scaler;
  }

  @override
  void didUpdateWidget(NovelReaderPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dialogueLayoutChanged = _updateDialogue();
    final textLayoutChanged = _updateTextStyles();
    if (!identical(oldWidget.document, widget.document)) {
      _restart(widget.target);
      return;
    }
    final jumped = oldWidget.jumpRevision != widget.jumpRevision;
    if (oldWidget.settings.contentWidth != widget.settings.contentWidth ||
        dialogueLayoutChanged ||
        textLayoutChanged) {
      // 同帧重排，避免将旧分页片段先放进变窄后的正文区域而溢出。
      _restart(jumped ? widget.target : _anchorNow());
      return;
    }
    if (oldWidget.settings.fontSize != widget.settings.fontSize ||
        oldWidget.settings.lineHeight != widget.settings.lineHeight ||
        oldWidget.settings.paragraphSpacing !=
            widget.settings.paragraphSpacing) {
      _scheduleRepaginate(jumped ? widget.target : _anchorNow());
      return;
    }
    if (jumped) {
      _restoreTarget(widget.target);
      return;
    }
    if (oldWidget.settings.instantPageTurn != widget.settings.instantPageTurn ||
        oldWidget.settings.realisticPageTurn !=
            widget.settings.realisticPageTurn) {
      final pending = _turnWillCommit ? _turnTarget : null;
      _cancelTurn();
      if (pending != null) {
        _currentPage = pending;
        _lastLocation = _locationForPage(pending) ?? _lastLocation;
        final serial = _turnSerial;
        // didUpdateWidget 属于构建阶段，宿主的进度/工具栏回调必须延后一帧。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _restoring || serial != _turnSerial) return;
          _emitPosition();
          widget.onPageTurned?.call();
        });
      }
    }
  }

  NovelReaderAnchor _anchorNow() =>
      _pendingAnchor ??
      _lastLocation?.anchor ??
      _paginator?.anchorForPage(_currentPage) ??
      widget.target;

  bool _isCurrent(int generation) => mounted && generation == _generation;

  // ── 分页构建 ──

  void _scheduleRepaginate(NovelReaderAnchor anchor) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restart(anchor);
    });
  }

  /// 整体重建分页（字体/行距/尺寸/文本缩放变化），并围绕 [anchor] 重新定位。
  void _restart(NovelReaderAnchor anchor) {
    if (_size == null) return;
    final generation = ++_generation;
    _buildTimer?.cancel();
    _restoring = true;
    final paginator = NovelReaderPaginator(
      document: widget.document,
      spec: _spec(_size!, _contentPadding ?? EdgeInsets.zero),
    );
    _paginator = paginator;
    unawaited(_pumpPagination(generation, anchor));
  }

  /// 构建到目标页可用，跳转并放行交互，随后后台续建剩余页。
  Future<void> _pumpPagination(int generation, NovelReaderAnchor anchor) async {
    final paginator = _paginator;
    if (paginator == null) return;
    // 分页重建会改变页码含义：中止进行中的卷曲，避免落到过期页。
    _cancelTurn();
    _pendingAnchor = anchor;
    setState(() => _paginationPending = true);
    final clock = Stopwatch()..start();
    while (paginator.pageForAnchor(anchor) == null && !paginator.complete) {
      paginator.buildMore(maxItems: 1);
      // 卷中改字重也要分片，不能同步分页整卷前缀。
      if (clock.elapsedMicroseconds >= 8000) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!_isCurrent(generation)) return;
        clock.reset();
      }
    }
    if (!_isCurrent(generation)) return;
    final target =
        paginator.pageForAnchor(anchor) ?? paginator.pages.length - 1;
    var page = target.clamp(0, math.max(0, paginator.pages.length - 1)).toInt();
    // 当前尾页仍在填充：把它封页后再展示，后台续建才不会让正文跳动。
    while (!paginator.complete && page == paginator.pages.length - 1) {
      paginator.buildMore(maxItems: 1);
      page = page.clamp(0, paginator.pages.length - 1);
      if (clock.elapsedMicroseconds >= 8000) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!_isCurrent(generation)) return;
        clock.reset();
      }
    }
    if (!_isCurrent(generation)) return;
    _paginationPending = false;
    _pendingAnchor = null;
    _currentPage = page;
    setState(() {});
    // 恢复期间先渲染一帧目标页再放行交互，避免用户看到旧页。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrent(generation)) return;
      setState(() => _restoring = false);
      _emitPosition();
      _scheduleBackgroundBuild(generation);
    });
  }

  /// 仅重新定位（滑杆跳转等）：分页已就绪，构建到目标页即可。
  void _restoreTarget(NovelReaderAnchor anchor) {
    if (_size == null) return;
    final generation = ++_generation;
    _buildTimer?.cancel();
    _restoring = true;
    unawaited(_pumpPagination(generation, anchor));
  }

  void _scheduleBackgroundBuild(int generation) {
    _buildTimer?.cancel();
    _buildTimer = Timer(const Duration(milliseconds: 16), () {
      if (!_isCurrent(generation)) return;
      _backgroundBuildStep(generation);
    });
  }

  void _backgroundBuildStep(int generation) {
    final paginator = _paginator;
    if (paginator == null || paginator.complete) return;
    final currentSlices = paginator.pages[_currentPage].slices.length;
    final target = _turnTarget;
    final targetSlices = target == null
        ? null
        : paginator.pages[target].slices.length;
    final stopwatch = Stopwatch()..start();
    while (!paginator.complete && stopwatch.elapsedMilliseconds < 8) {
      paginator.buildMore(maxItems: 1);
    }
    if (!_isCurrent(generation)) return;
    // 后台新增后续页面不应反复构建当前页的富文本子树。
    if (currentSlices != paginator.pages[_currentPage].slices.length ||
        (target != null &&
            targetSlices != paginator.pages[target].slices.length)) {
      setState(() {});
    }
    if (!paginator.complete) _scheduleBackgroundBuild(generation);
  }

  /// 正文最终样式：与 [Text] 内部一致地把主题样式合并到 DefaultTextStyle
  /// 上。分页测量与页面渲染必须共用同一份样式，否则行高/换行会漂移。
  TextStyle _bodyStyle(BuildContext context) => novelContentTextStyle(
    DefaultTextStyle.of(context).style.merge(
      Theme.of(context).textTheme.bodyLarge!.copyWith(
        color: widget.palette.foreground,
        fontSize: widget.settings.fontSize,
        height: widget.settings.lineHeight,
      ),
    ),
    widget.fontFamily,
  );

  TextStyle _titleStyle(BuildContext context) => novelContentTextStyle(
    DefaultTextStyle.of(context).style.merge(
      Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: widget.palette.foreground,
          ) ??
          const TextStyle(),
    ),
    widget.fontFamily,
  );

  NovelPaginationSpec _spec(Size size, EdgeInsets contentPadding) {
    final metrics = novelPageMetricsFor(
      size,
      contentPadding,
      maxContentWidth: widget.settings.contentWidth,
    );
    return NovelPaginationSpec(
      textStyle: _bodyStyle(context),
      titleStyle: _titleStyle(context),
      textScaler: _textScaler ?? TextScaler.noScaling,
      textDirection: Directionality.of(context),
      size: Size(
        metrics.width,
        math.max(0, size.height - contentPadding.vertical),
      ),
      viewportHeight: size.height,
      contentTopInset: contentPadding.top,
      paragraphSpacing: widget.settings.paragraphSpacing,
      titleSpacing: AppSpacing.xxl,
      emptyChapterText: widget.emptyChapterText,
      dialogue: _dialogue,
    );
  }

  // ── 翻页 ──

  /// 一次翻页动画（含拖动）尚未落定。
  bool get _turning => _turnTarget != null;

  void _turn({required bool forward, double? originY}) {
    final paginator = _paginator;
    if (_restoring || paginator == null) return;
    final pending = _turnTarget;
    if (pending != null) {
      // 连点加速已确认的翻页；未确认的拖动/取消回弹不能额外提交一页。
      if (_turnWillCommit) {
        _commitTurn(pending);
      } else {
        _resetTurn();
      }
    }
    final target = _currentPage + (forward ? 1 : -1);
    if (!_ensurePage(target)) {
      widget.onBoundary?.call(forward);
      return;
    }
    if (widget.settings.instantPageTurn) {
      _commitTurn(target);
      return;
    }
    _beginTurn(target, forward: forward, originY: originY ?? _turnOriginY);
    unawaited(_finishTurn(commit: true));
  }

  bool _ensurePage(int target) {
    final paginator = _paginator;
    if (paginator == null || target < 0) return false;
    if (target >= paginator.pages.length) {
      // 后台分页尚未覆盖目标页：先同步补齐，不能误当成卷末。
      while (target >= paginator.pages.length && paginator.buildMore()) {}
      setState(() {});
    }
    return target < paginator.pages.length;
  }

  void _resetTurn() {
    ++_turnSerial;
    _turnController.stop();
    _turnController.value = 0;
    _turnTarget = null;
    _turnWillCommit = false;
    _dragTurnSerial = null;
  }

  void _commitTurn(int target) {
    _resetTurn();
    _currentPage = target;
    setState(() {});
    _emitPosition();
    widget.onPageTurned?.call();
  }

  void _beginTurn(
    int target, {
    required bool forward,
    required double originY,
  }) {
    _resetTurn();
    _turnTarget = target;
    _turnForward = forward;
    _turnOriginY = originY.clamp(0.0, 1.0);
    setState(() {});
  }

  /// 松手后的时长随剩余距离缩短；序号与取消异常阻止旧动画回写页码。
  Future<void> _finishTurn({required bool commit}) async {
    final target = _turnTarget;
    if (target == null) return;
    final serial = _turnSerial;
    _turnWillCommit = commit;
    try {
      if (widget.settings.instantPageTurn) {
        _turnController.value = commit ? 1 : 0;
      } else if (commit) {
        await _turnController.animateTo(1, curve: Curves.easeOutCubic).orCancel;
      } else {
        await _turnController
            .animateBack(0, curve: Curves.easeOutCubic)
            .orCancel;
      }
    } on TickerCanceled {
      // 新翻页、重分页或页面销毁会主动取消旧动画，无需落页。
      return;
    }
    if (!mounted || serial != _turnSerial || _turnTarget != target) return;
    if (commit) {
      _commitTurn(target);
    } else {
      _resetTurn();
      setState(() {});
    }
  }

  /// 重分页/跳转/切换动画类型时作废当前手势和动画。
  void _cancelTurn() {
    _dragBlocked = true;
    _dragCommitted = false;
    _dragOutOfBounds = false;
    _resetTurn();
  }

  NovelReaderLocation? _locationForPage(int page) {
    final paginator = _paginator;
    if (paginator == null || page < 0 || page >= paginator.pages.length) {
      return null;
    }
    return paginator.locationForPage(page);
  }

  void _emitPosition() {
    final location = _locationForPage(_currentPage);
    if (location == null) return;
    _lastLocation = location;
    widget.onPosition(location);
  }

  void _handleTap(Offset globalPosition) {
    if (_restoring) return;
    if (widget.toolbarVisible) {
      widget.onTap();
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    final width = _size?.width ?? box?.size.width ?? 0;
    if (box == null || width <= 0) return;
    final local = box.globalToLocal(globalPosition);
    if (local.dx < width / 3) {
      _turn(forward: false, originY: _originYFor(local.dy));
    } else if (local.dx > width * 2 / 3) {
      _turn(forward: true, originY: _originYFor(local.dy));
    } else {
      widget.onTap();
    }
  }

  /// 落点纵坐标换算成 0..1 的卷曲原点：点击越靠下，纸角从越靠下处翻起。
  double _originYFor(double localY) {
    final height = _size?.height ?? 0;
    if (height <= 0) return _turnOriginY;
    return (localY / height).clamp(0.0, 1.0);
  }

  // ── 翻页拖动：与页面卷曲进度实时联动，松手后按阈值落定或退回 ──

  void _onTurnDragStart(DragStartDetails details) {
    _dragDelta = 0;
    _dragCommitted = false;
    _dragOutOfBounds = false;
    _dragTurnSerial = null;
    _dragBlocked = _restoring || _turning;
    if (_dragBlocked) return;
    final box = context.findRenderObject() as RenderBox?;
    _dragOriginY = box == null
        ? _turnOriginY
        : _originYFor(box.globalToLocal(details.globalPosition).dy);
  }

  void _onTurnDragUpdate(DragUpdateDetails details) {
    if (_dragBlocked || _restoring) return;
    _dragDelta += details.delta.dx;
    final width = _size?.width ?? MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    if (widget.settings.instantPageTurn) {
      if (_dragCommitted) return;
      if (_dragDelta.abs() >= width * 0.2) {
        // 去重标记属于手势，不随页码落定重置。
        _dragCommitted = true;
        _turn(forward: _dragDelta < 0);
      }
      return;
    }
    final progress = (_dragDelta.abs() / width).clamp(0.0, 1.0);
    final forward = _dragDelta < 0;
    final target = _currentPage + (forward ? 1 : -1);
    _dragOutOfBounds = false;
    if (progress == 0 || !_ensurePage(target)) {
      if (_dragTurnSerial != null) {
        _resetTurn();
        _dragCommitted = false;
        setState(() {});
      }
      _dragOutOfBounds = _dragDelta.abs() >= width * 0.12;
      _dragForward = forward;
      return;
    }
    if (_dragTurnSerial == null || _turnForward != forward) {
      _beginTurn(target, forward: forward, originY: _dragOriginY);
      _dragTurnSerial = _turnSerial;
      _dragCommitted = true;
    }
    _turnController.value = progress;
  }

  void _onTurnDragEnd(DragEndDetails details) {
    final ownsTurn = _dragTurnSerial != null && _dragTurnSerial == _turnSerial;
    final outOfBounds = _dragOutOfBounds;
    final dragForward = _dragForward;
    final progress = _turnController.value;
    final width = _size?.width ?? MediaQuery.sizeOf(context).width;
    final velocity = details.velocity.pixelsPerSecond.dx;
    _dragDelta = 0;
    _dragCommitted = false;
    _dragOutOfBounds = false;
    _dragTurnSerial = null;
    if (_dragBlocked) {
      _dragBlocked = false;
      return;
    }
    if (widget.settings.instantPageTurn) return;
    if (outOfBounds) {
      _turn(forward: dragForward);
      return;
    }
    if (!ownsTurn) return;
    final fastEnough =
        width > 0 && (_turnForward ? -velocity : velocity) > width * 0.6;
    unawaited(_finishTurn(commit: progress >= 0.34 || fastEnough));
  }

  void _onTurnDragCancel() {
    final ownsTurn = _dragTurnSerial != null && _dragTurnSerial == _turnSerial;
    _dragBlocked = false;
    _dragDelta = 0;
    _dragCommitted = false;
    _dragOutOfBounds = false;
    _dragTurnSerial = null;
    // 点击/长按赢得手势竞争也会发 cancel，不能撤销它们之前确认的翻页。
    if (ownsTurn) unawaited(_finishTurn(commit: false));
  }

  @override
  void dispose() {
    ++_generation;
    _buildTimer?.cancel();
    _turnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final contentPadding = widget.contentPadding;
        final sizeChanged = _size != size;
        final paddingChanged = _contentPadding != contentPadding;
        _size = size;
        _contentPadding = contentPadding;
        if (sizeChanged || paddingChanged) {
          final anchor = _paginator == null ? widget.target : _anchorNow();
          _scheduleRepaginate(anchor);
        }
        final paginator = _paginator;
        if (paginator == null || _paginationPending) {
          return const Center(child: ExpressiveLoadingIndicator());
        }
        return AbsorbPointer(
          absorbing: _restoring,
          child: GestureDetector(
            key: const ValueKey('novel-page-surface'),
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) => _handleTap(details.globalPosition),
            onHorizontalDragStart: _onTurnDragStart,
            onHorizontalDragUpdate: _onTurnDragUpdate,
            onHorizontalDragEnd: _onTurnDragEnd,
            onHorizontalDragCancel: _onTurnDragCancel,
            child: _buildPageSurface(context, paginator),
          ),
        );
      },
    );
  }

  /// 静止时只渲染当前页；翻页中把「被翻起的页」与「露出的页」交给
  /// [NovelPageCurl]，纸背用同一页内容的独立实例（镜像文字）。
  Widget _buildPageSurface(
    BuildContext context,
    NovelReaderPaginator paginator,
  ) {
    final target = _turnTarget;
    if (target == null || target < 0 || target >= paginator.pages.length) {
      return KeyedSubtree(
        key: const ValueKey('novel-reader-pages'),
        child: _buildPageSheet(context, _currentPage),
      );
    }
    if (!widget.settings.realisticPageTurn) {
      final current = RepaintBoundary(
        child: _buildPageSheet(context, _currentPage),
      );
      final next = RepaintBoundary(child: _buildPageSheet(context, target));
      final direction = _turnForward ? -1.0 : 1.0;
      return ClipRect(
        key: const ValueKey('novel-reader-pages'),
        child: AnimatedBuilder(
          animation: _turnController,
          builder: (context, _) {
            final value = _turnController.value;
            return Stack(
              key: const ValueKey('novel-page-slide'),
              fit: StackFit.expand,
              children: [
                FractionalTranslation(
                  translation: Offset(direction * value, 0),
                  child: current,
                ),
                FractionalTranslation(
                  translation: Offset(-direction * (1 - value), 0),
                  child: next,
                ),
              ],
            );
          },
        ),
      );
    }
    final turningIndex = _turnForward ? _currentPage : target;
    final underneathIndex = _turnForward ? target : _currentPage;
    return NovelPageCurl(
      key: const ValueKey('novel-reader-pages'),
      animation: _turnController,
      forward: _turnForward,
      originY: _turnOriginY,
      paperColor: widget.palette.background,
      turningPage: _buildPageSheet(context, turningIndex),
      turningPageBack: _buildPageSheet(context, turningIndex),
      underneath: _buildPageSheet(context, underneathIndex),
    );
  }

  /// 整张纸参与翻页，正文边距仍与分页测量一致，不能只卷动文字区域。
  Widget _buildPageSheet(BuildContext context, int index) {
    final size = _size!;
    final padding = widget.contentPadding;
    final metrics = novelPageMetricsFor(
      size,
      padding,
      maxContentWidth: widget.settings.contentWidth,
    );
    return ColoredBox(
      color: widget.palette.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          padding.left + metrics.horizontalPadding,
          padding.top,
          padding.right + metrics.horizontalPadding,
          padding.bottom,
        ),
        child: _buildPage(context, index),
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    final paginator = _paginator!;
    final page = paginator.pages[index];
    final style = _bodyStyle(context);
    final children = <Widget>[];
    final slices = page.slices;
    for (var sliceIndex = 0; sliceIndex < slices.length; sliceIndex++) {
      final slice = slices[sliceIndex];
      final isLastOfPage = sliceIndex == slices.length - 1;
      final paragraph = widget.document.paragraphAt(slice.itemIndex);
      final entry = paragraph.entry;
      if (slice.hasTitle) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Text(entry.name, style: _titleStyle(context)),
          ),
        );
      }
      final styled = novelParagraphDialogue(paragraph, _dialogue);
      final display =
          styled?.text ??
          novelParagraphDisplayText(paragraph, widget.emptyChapterText);
      final start = slice.startOffset.clamp(0, display.length);
      final end = slice.endOffset.clamp(start, display.length);
      final isFinalSlice = end >= display.length;
      Widget body = styled == null || styled.ranges.isEmpty
          ? Text(
              display.substring(start, end),
              style: style,
              textScaler: _textScaler,
              textWidthBasis: TextWidthBasis.parent,
            )
          : NovelDialogueText(
              paragraph: styled,
              baseStyle: style,
              dialogue: _dialogue,
              start: start,
              end: end,
              textScaler: _textScaler,
            );
      final highlighted =
          slice.startLine == 0 &&
          widget.highlight != null &&
          widget.highlight!.entryIndex == entry.entryIndex &&
          widget.highlight!.paragraphIndex == paragraph.paragraphIndex &&
          (widget.highlight!.volumeId.isEmpty ||
              widget.highlight!.volumeId == paragraph.volumeId);
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
      children.add(
        Padding(
          key: ValueKey(
            'novel-page-${entry.entryIndex}-${paragraph.paragraphIndex}-'
            '${slice.startLine}',
          ),
          // 段距是段与段之间的分隔，页面末尾不需要：分页测量已把段距
          // 计入页高，若最后一个片段再加一次，渲染会高出页面（溢出）。
          padding: EdgeInsets.only(
            bottom: isFinalSlice && !isLastOfPage
                ? widget.settings.paragraphSpacing
                : 0,
          ),
          child: body,
        ),
      );
    }
    return Align(
      alignment: Alignment.topLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
