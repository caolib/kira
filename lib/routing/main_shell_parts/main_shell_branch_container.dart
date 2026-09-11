part of '../main_shell.dart';

/// Dual-page linked slide between shell branches (no intermediate-page sweep).
///
/// Hidden tabs stay mounted offstage so branch state is preserved, and get
/// pre-warmed (painted once) shortly after startup so the first swipe onto
/// them doesn't hitch on first-time paint/raster cost.
///
/// Branch container: two slide models sharing one AnimationController.
///
/// - 点按导航：双页联动直滑（旧行为），目标与当前页互为进出，不扫过中间页。
/// - 拖动跟手：连续滚动位置 [_AnimatedBranchContainerState._scrollPos]
///   （单位：页宽），页 i 平移量 = 可见序(i) − _scrollPos；松手收尾向相邻页
///   补间到位后由父级 goBranch 确认。
class _AnimatedBranchContainer extends StatefulWidget {
  const _AnimatedBranchContainer({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<_AnimatedBranchContainer> createState() =>
      _AnimatedBranchContainerState();
}

class _AnimatedBranchContainerState extends State<_AnimatedBranchContainer>
    with SingleTickerProviderStateMixin {
  static const _duration = kTabScrollDuration;

  /// 与旧行为一致的甩动翻页速度阈值（px/s）。
  static const _flingVelocity = 400.0;

  /// 慢拖翻页的位移阈值（页宽比例，≈1/20 屏宽；对齐旧行为的 48px/800px）。
  static const _pageFlingThreshold = 0.06;

  late final AnimationController _controller;
  Animation<double>? _tween;

  late List<String> _orderedKeys;
  bool _reduceMotion = false;

  /// 连续滚动位置（可见页单位），静止时恒为整数页位。
  double _scrollPos = 0;

  /// 手势交互期间接收指针的真实分支。滑动未确认前保持旧值，避免指针中途
  /// 落到尚未到达的新页上。
  int _logicalBranch = 0;

  /// 跟手拖动中。
  bool _dragging = false;

  /// 本次手势累计位移（px，右滑为正）。
  double _dragAccumPx = 0;

  /// 拖动开始时相对逻辑页位的既有偏移（上次收尾被打断时的残余），保证连续。
  double _dragBaseProgress = 0;

  /// 松手收尾后等待父级 goBranch 确认的目标分支；确认前 UI 视觉已到位，
  /// didUpdateWidget 收到同分支变化时只认领逻辑页，不重放动画。
  int? _pendingBranch;

  /// 双页直滑（点按导航）的出场页与方向；[._outgoingIndex] 为 null 即无此动画。
  int? _outgoingIndex;
  double _direction = 1;

  /// 当前补间的几何模型：true=双页直滑（点按），false=连续位置（拖动收尾），
  /// null=无补间进行中。
  bool? _dualTween;

  /// 正在预热的分支。启动稳定后让隐藏分支各绘制一帧（画在栈底、被当前页
  /// 盖住），把首次显示才发生的整页绘制+光栅化成本从滑动过程里挪走。
  int? _warmBranch;
  final Set<int> _warmedBranches = {};

  /// 预热被滑动/切换打断后的重试次数（避免无限重试）。
  int _warmUpRetries = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration);
    _controller.addListener(_onTick);
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _tween = null;
      _dualTween = null;
      setState(() => _outgoingIndex = null);
    });
    _logicalBranch = widget.currentIndex;
    _scheduleWarmUp();
  }

  void _onTick() {
    final tween = _tween;
    if (tween == null) return;
    // 双页直滑的进度由 build 直接读 tween，不占用 _scrollPos（那是
    // 连续位置模型的状态；误写会让动画结束时页面停在错误的页位上）。
    if (_dualTween == true) return;
    setState(() => _scrollPos = tween.value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _orderedKeys = _visibleNavKeys(UserManager());
    _reduceMotion = prefersReducedMotion(context);
    _controller.duration = _reduceMotion ? Duration.zero : _duration;
    if (!_dragging && _pendingBranch == null && _outgoingIndex == null) {
      _scrollPos = _visiblePos(widget.currentIndex);
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedBranchContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldKeys = _orderedKeys;
    _orderedKeys = _visibleNavKeys(UserManager());

    // 可见序变化（如登录后插入书架）会让所有可见页位整体平移，而分支
    // 索引不变、上面的分支变化分支不会进入；静止态直接按逻辑分支重算
    // 页位，否则 _scrollPos 停在旧页位上会显示错误的分支。
    if (oldKeys.join('\u0000') != _orderedKeys.join('\u0000') &&
        !_dragging &&
        _pendingBranch == null &&
        _outgoingIndex == null) {
      _scrollPos = _visiblePos(widget.currentIndex);
    }

    if (oldWidget.currentIndex == widget.currentIndex) return;

    final newPos = _visiblePos(widget.currentIndex);

    // 松手收尾的目标被父级确认：连续位置动画已经在路上，只认领逻辑分支。
    if (_pendingBranch == widget.currentIndex && !_dragging) {
      setState(() {
        _logicalBranch = widget.currentIndex;
        _pendingBranch = null;
        _outgoingIndex = null;
      });
      return;
    }

    if (_dragging) _abortDrag();
    _pendingBranch = null;

    // 点按导航：恢复旧行为——目标页与当前页双页联动直滑，不扫过中间页。
    setState(() {
      _logicalBranch = widget.currentIndex;
      _outgoingIndex = oldWidget.currentIndex;
      _direction = newPos >= _visiblePos(oldWidget.currentIndex) ? 1 : -1;
      if (_reduceMotion) {
        _tween = null;
        _dualTween = null;
        _controller.stop();
        _scrollPos = newPos;
        _outgoingIndex = null;
      } else {
        _scrollPos = newPos;
        _startDualTween();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _uiBranch => (_dragging || _pendingBranch != null)
      ? _logicalBranch
      : widget.currentIndex;

  double _visiblePos(int branchIndex) {
    final navKey = _navKeyToBranchIndex.entries
        .where((entry) => entry.value == branchIndex)
        .map((entry) => entry.key)
        .firstOrNull;
    final visibleIndex = navKey == null ? -1 : _orderedKeys.indexOf(navKey);
    return visibleIndex < 0 ? branchIndex.toDouble() : visibleIndex.toDouble();
  }

  /// 启动「连续位置」补间：_scrollPos 从 from 滑到 to（拖动收尾用）。
  void _startTween(double from, double to, Duration duration) {
    _warmBranch = null;
    _dualTween = false;
    _tween = Tween<double>(
      begin: from,
      end: to,
    ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);
    _controller.duration = duration;
    _controller.forward(from: 0);
  }

  /// 启动「双页直滑」补间：0→1 进度驱动 _outgoingIndex 两页互滑（点按导航）。
  void _startDualTween() {
    _warmBranch = null;
    _dualTween = true;
    _tween = Tween<double>(
      begin: 0,
      end: 1,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_controller);
    _controller.duration = _reduceMotion ? Duration.zero : _duration;
    if (_reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  // ---- 跟手拖动（由 MainShell 转发手势回调） ----

  void dragBegin(DragStartDetails details) {
    if (_dragging) return;
    // 打断进行中的收尾/切换动画。点按的双页直滑没有连续位置语义，
    // 直接终止跳到终态（动画仅 ~300ms，中途被打断感知不到）。
    _controller.stop();
    _tween = null;
    _dualTween = null;
    _outgoingIndex = null;
    _pendingBranch = null;
    _warmBranch = null;
    _dragging = true;
    _dragAccumPx = 0;
    _dragBaseProgress = _scrollPos - _visiblePos(_uiBranch);
  }

  void dragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final width = context.size?.width ?? 0;
    if (width <= 0) return;
    _dragAccumPx += details.primaryDelta ?? 0;
    var progress = _dragBaseProgress - _dragAccumPx / width;

    // 边界钳制：progress<0 是往上一页方向——首页没有上一页，钳住；
    // 末页没有下一页同理（PageView 行为）。
    final cur = _visiblePos(_uiBranch);
    if (cur <= 0 && progress < 0) progress = 0;
    if (cur >= _orderedKeys.length - 1 && progress > 0) progress = 0;
    progress = progress.clamp(-1.0, 1.0);

    setState(() => _scrollPos = cur + progress);
  }

  /// 当前拖动进度（负值表示朝下一页方向）。
  double get _dragProgress {
    final width = context.size?.width ?? 0;
    if (width <= 0 || !_dragging) return 0;
    return (_scrollPos - _visiblePos(_uiBranch)).clamp(-1.0, 1.0);
  }

  /// 松手收尾：按位移过半或甩动方向决定落到相邻页还是弹回，
  /// 返回应提交的可见序（无切换时返回 null）。调用方随后 goBranch 确认。
  int? settleFromPointer(DragEndDetails details) {
    if (!_dragging) return null;
    final cur = _visiblePos(_uiBranch);
    final velocity = details.primaryVelocity ?? 0;

    var target = 0;
    // 拖动进度 p = _S − cur：向左滑为正（朝下一页）。
    // 翻页条件对齐旧行为：慢拖超过 ~1/20 屏宽即翻（同 PageView 的宽容度，
    // 也让 widget 测试里 tester.drag 的无速度拖动能触发），快速甩动看速度方向。
    final progress = _dragProgress;
    if (velocity.abs() >= _flingVelocity) {
      target = velocity.sign < 0 ? 1 : -1;
    } else if (progress >= _pageFlingThreshold) {
      target = 1;
    } else if (progress <= -_pageFlingThreshold) {
      target = -1;
    }

    // 目标页越界则原地弹回。
    final destIndex = (cur.round() + target).clamp(0, _orderedKeys.length - 1);
    target = destIndex - cur.round();

    _dragging = false;
    _dragAccumPx = 0;
    _dragBaseProgress = 0;

    final dest = cur + target.toDouble();
    if ((dest - _scrollPos).abs() < 0.0005) {
      _scrollPos = dest;
      setState(() {});
      return target == 0 ? null : destIndex;
    }
    if (target != 0) _pendingBranch = _branchAtVisiblePos(destIndex);
    setState(() {});
    if (_reduceMotion) {
      _tween = null;
      _controller.stop();
      _scrollPos = dest;
      setState(() {});
    } else {
      // 快速轻甩时距离短，收尾节奏随剩余距离缩短，避免「一甩等半秒」。
      final remaining = (dest - _scrollPos).abs();
      _startTween(
        _scrollPos,
        dest,
        Duration(milliseconds: (120 + 180 * remaining).round()),
      );
    }
    return target == 0 ? null : destIndex;
  }

  int _branchAtVisiblePos(int visibleIndex) {
    for (final entry in _navKeyToBranchIndex.entries) {
      if (_orderedKeys.indexOf(entry.key) == visibleIndex) return entry.value;
    }
    return visibleIndex;
  }

  void dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _dragAccumPx = 0;
    _dragBaseProgress = 0;
    final dest = _visiblePos(_uiBranch);
    if ((dest - _scrollPos).abs() < 0.0005) {
      _scrollPos = dest;
      setState(() {});
      return;
    }
    if (_reduceMotion) {
      _tween = null;
      _controller.stop();
      _scrollPos = dest;
      setState(() {});
    } else {
      _startTween(
        _scrollPos,
        dest,
        Duration(milliseconds: (120 + 180 * (dest - _scrollPos).abs()).round()),
      );
    }
  }

  /// 不播放收尾动画地终止拖动状态（例如父级在拖动中切换了分支）。
  void _abortDrag() {
    _dragging = false;
    _dragAccumPx = 0;
    _dragBaseProgress = 0;
  }

  // ---- 隐藏分支预热 ----

  /// 有拖动或切换动画进行中（此时当前页不在原位，盖不住预热页）。
  bool get _transitionBusy =>
      _dragging ||
      _pendingBranch != null ||
      _outgoingIndex != null ||
      _tween != null;

  void _scheduleWarmUp() {
    // 等首帧画完、启动流程跑起来一小段再开始，避免和启动抢帧。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 1200), _warmNextBranch);
    });
  }

  void _warmNextBranch() {
    if (!mounted) return;
    // 预热页画在栈底、依赖当前页原位盖住它，所以忙碌时延后再试。
    if (_transitionBusy) {
      if (_warmUpRetries >= 10) return;
      _warmUpRetries++;
      Future.delayed(const Duration(milliseconds: 400), _warmNextBranch);
      return;
    }
    var next = -1;
    for (var i = 0; i < widget.children.length; i++) {
      if (i == _uiBranch || _warmedBranches.contains(i)) continue;
      if (!_isBranchReachable(i)) continue;
      next = i;
      break;
    }
    if (next < 0) return;
    _warmUpRetries = 0;
    setState(() => _warmBranch = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _warmedBranches.add(next);
      if (_warmBranch == next) _warmBranch = null;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 60), _warmNextBranch);
    });
  }

  /// 分支是否出现在可见导航序里（被设置隐藏的分支用户到不了，不用预热）。
  bool _isBranchReachable(int branchIndex) {
    for (final entry in _navKeyToBranchIndex.entries) {
      if (entry.value == branchIndex) return _orderedKeys.contains(entry.key);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final order = List<int>.generate(widget.children.length, (i) => i);
        final warm = _warmBranch;
        if (warm != null) {
          // 预热页挪到栈底：完整绘制、被当前页盖住，用户无感。
          order
            ..remove(warm)
            ..insert(0, warm);
        }
        return Stack(
          fit: StackFit.expand,
          children: [for (final index in order) _buildBranch(index)],
        );
      },
    );
  }

  Widget _buildBranch(int index) {
    final isLogical = index == _uiBranch;
    final isOutgoing = index == _outgoingIndex;
    final isWarming = index == _warmBranch;

    // 所有分支共用同一套 widget 结构，只在属性值上区分状态：
    // Offstage > TickerMode > IgnorePointer > FractionalTranslation > RepaintBoundary。
    // 结构若随「是否参与滑动」分叉，Flutter 调和会把整棵分支子树销毁重建
    // （只靠分支 Navigator 的 GlobalKey 补挂回来保状态），切页那一帧就得
    // 付出整页重排 + 重绘，首次显示还要叠加首次光栅化，表现成滑动卡顿。
    var offstage = false;
    var dx = 0.0;

    if (_dualTween == true && _tween != null && !isLogical && !isOutgoing) {
      // 点按直滑时，无关分支保持隐藏。
      offstage = true;
      dx = _visiblePos(index) - _scrollPos;
    } else if (_dualTween == true && _tween != null) {
      // 双页直滑（点按导航）：目标页自 ±1 滑到 0，出场页自 0 滑到 ∓1。
      final t = _tween!.value;
      dx = isLogical ? (1 - t) * _direction : -t * _direction;
    } else {
      // 连续位置模型（拖动 / 收尾补间 / 静止）：页 i 平移量 = 可见序(i) − _scrollPos。
      // 静止时相邻页 |dx| 恰为 1，靠 offstage 挡住不画；预热页强制画在原位。
      dx = isWarming ? 0.0 : _visiblePos(index) - _scrollPos;
      offstage = !isWarming && dx.abs() >= 1;
    }

    return Offstage(
      key: ValueKey(index),
      offstage: offstage,
      child: TickerMode(
        enabled: isLogical,
        child: IgnorePointer(
          ignoring: !isLogical,
          child: FractionalTranslation(
            translation: Offset(dx, 0),
            child: RepaintBoundary(child: widget.children[index]),
          ),
        ),
      ),
    );
  }
}
