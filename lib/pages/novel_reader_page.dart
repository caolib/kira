import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/novel/novel_api.dart';
import '../l10n/app_localizations.dart';
import '../models/novel.dart';
import '../models/novel_reader_settings.dart';
import '../models/novel_reader_status_settings.dart';
import '../models/novel_reading_progress.dart';
import '../providers/novel_providers.dart';
import '../repositories/novel_reader_source.dart';
import '../repositories/novel_repository.dart';
import '../routing/app_router.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../theme/novel_reader_theme.dart';
import '../theme/reader_chrome.dart';
import '../utils/adaptive_motion.dart';
import '../utils/app_logger.dart';
import '../utils/novel_bookmark_store.dart';
import '../utils/novel_reading_store.dart';
import '../utils/toast.dart';
import '../widgets/app_sheet.dart';
import '../widgets/error_retry_view.dart';
import '../widgets/reader_status_overlay.dart';
import 'novel_reader/novel_chapter_slider_track_shape.dart';
import 'novel_reader/novel_focus_mask.dart';
import 'novel_reader/novel_reader_contents_sheet.dart';
import 'novel_reader/novel_reader_dialogue.dart';
import 'novel_reader/novel_reader_document.dart';
import 'novel_reader/novel_reader_font.dart';
import 'novel_reader/novel_reader_illustrations.dart';
import 'novel_reader/novel_reader_page_view.dart';
import 'novel_reader/novel_reader_settings_sheet.dart';
import 'novel_reader/novel_reader_viewport.dart';

part 'novel_reader_page_parts/continuous.dart';
part 'novel_reader_page_parts/view.dart';

class NovelReaderPage extends ConsumerStatefulWidget {
  const NovelReaderPage({
    super.key,
    required this.pathWord,
    required this.volumeId,
    this.name = '',
    this.cover = '',
    this.initialEntryIndex = 0,
    this.initialParagraphIndex = 0,
    this.initialParagraphAlignment = 0,
    this.resume = false,
    this.preferDownloads = false,
    this.noDetailBelow = false,
    this.highlightOnEntry = false,
    this.source,
  });

  final String pathWord;
  final String volumeId;
  final String name;
  final String cover;
  final int initialEntryIndex;
  final int initialParagraphIndex;
  final double initialParagraphAlignment;
  final bool resume;

  /// 本地入口先初始化下载目录，缺失内容仍允许在线加载。
  final bool preferDownloads;

  /// 栈底是否没有小说详情页（书架/历史/书签/继续阅读等直达入口）。
  /// 「总目录」退出时据此决定 pop 还是原地替换成详情页。
  final bool noDetailBelow;

  /// 从书签进入：目标段落短暂高亮，提示书签指向的具体位置。
  final bool highlightOnEntry;

  final NovelReaderSource? source;

  @override
  ConsumerState<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends ConsumerState<NovelReaderPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  /// 与漫画阅读器共用同一个音量键通道；同一时刻只有一个阅读页在前台，
  /// 各自在 init/dispose 与设置变化时同步 enable/disable，避免双重拦截。
  static const _volumeChannel = MethodChannel('io.github.caolib.kira/volume');
  late final NovelRepository _repository;
  late NovelReaderSource _source;
  late final NovelApi _api;
  late final NovelReadingStore _store;
  late final NovelBookmarkStore _bookmarks;
  // 状态组件配置与漫画阅读器相互独立（开关/位置/段位/颜色）。
  late final NovelReaderStatusSettings _statusSettings =
      NovelReaderStatusSettings()..addListener(_onStatusSettingsChanged);
  bool _bookmarksLoaded = false;
  bool _bookmarking = false;
  GlobalKey<NovelReaderViewportState> _viewportKey = GlobalKey();
  GlobalKey<NovelReaderPageViewState> _pageViewKey = GlobalKey();
  NovelReaderSettings _settings = const NovelReaderSettings();
  String? _contentFontFamily;
  NovelVolumeContent? _content;
  NovelVolumeDetail? _accessDetail;
  NovelTextDocument? _document;

  // ── 滚动模式连续阅读（卷尾下滑进入下一卷、卷首回滑拼接上一卷）──
  /// 卷栈：当前卷及相邻卷（最多两卷）。手动跳卷/换卷时重置。
  final _stackVolumes = <NovelReaderVolumeDocument>[];
  final _stackContents = <String, NovelVolumeContent>{};
  final _stackLoads = <String, Future<NovelVolumeContent>>{};

  /// 只读缓存的预取结果：与实际阅读加载分开，缓存未命中不能挡住正常加载。
  final _stackPrefetches = <String, Future<NovelVolumeContent>>{};
  NovelReaderStack? _stack;
  int _contentRevision = 0;
  bool _appending = false;
  bool _prepending = false;
  Object? _seamError;
  bool _seamUnavailable = false;
  Object? _headSeamError;
  bool _headSeamUnavailable = false;
  NovelReaderLocation? _location;
  NovelReaderAnchor _target = const NovelReaderAnchor(entryIndex: 0);
  NovelReadingProgress? _pendingProgress;
  List<NovelVolume> _volumes = [];
  bool _volumesReady = false;
  Future<List<NovelVolume>>? _volumesLoad;
  final _volumeDetails = <String, NovelVolumeDetail>{};
  Object? _error;
  Timer? _saveTimer;
  Future<void> _lastWrite = Future<void>.value();
  static Future<void>? _wakeQueue;
  DateTime _lastTimestamp = DateTime.fromMillisecondsSinceEpoch(0);
  late String _pathWord;
  late String _volumeId;
  late String _fallbackName;
  late String _fallbackCover;
  int _session = 0;
  int _request = 0;
  int _settingsRevision = 0;
  int _jumpRevision = 0;

  /// 阅读位置只通知进度与工具栏，不带动正文重新构建。
  final _locationRevision = ValueNotifier<int>(0);
  ThemeData? _readerTheme;
  ThemeData? _readerThemeBase;
  NovelReaderPalette? _readerThemePalette;
  bool _volumeChannelAvailable = true;
  bool _loading = true;
  bool _toolbarVisible = false;
  bool _settingsDragPreview = false;

  /// 工具栏滑出屏幕的位移倍数（留一点余量，避免边缘露出）。
  static const _hiddenToolbarSlideOffset = 1.05;

  /// 短暂高亮的书签段落；定时自动清除，滚动或跳转提前清除。
  static const _highlightDuration = Duration(milliseconds: 2500);
  NovelReaderAnchor? _highlight;
  Timer? _highlightTimer;

  /// 高亮卡片的淡入淡出：出现 180ms、消失 400ms；「减少动画」时直接
  /// 跳到目标值。画笔挂在该动画上逐帧重绘，高亮不触发整树 rebuild。
  AnimationController? _highlightFade;

  /// 高亮代数：新一次高亮会使上一次未完成的淡出作废，防止迟到的
  /// whenComplete 把新高亮一并清掉。
  int _highlightGen = 0;

  /// 从书签进入时待生效的高亮锚点：等卷内容加载、锚点解析后再应用，
  /// 避免高亮显示在错误位置（如 resume 改变了落点时丢弃）。
  NovelReaderAnchor? _pendingEntryHighlight;

  /// 进入页面时的系统栏内边距快照。工具栏显隐会切换沉浸模式，
  /// MediaQuery.padding 随之变化；正文用它作列表内容层的固定 inset
  /// （viewport 本身全屏恒定），避免触发 anchor restoration。
  EdgeInsets? _systemPadding;

  bool _disposed = false;
  bool _offline = false;
  double? _sliderValue;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(novelRepositoryProvider);
    _api = ref.read(novelApiProvider);
    _store = ref.read(novelReadingStoreProvider);
    _bookmarks = ref.read(novelBookmarkStoreProvider)
      ..addListener(_onBookmarksChanged);
    unawaited(_loadBookmarks());
    WidgetsBinding.instance.addObserver(this);
    // 与漫画阅读器一致：阅读期间窗口允许延伸进刘海/挖孔区（SHORT_EDGES）。
    // 否则沉浸模式下挖孔区域不随窗口扩展，露出一条纯黑的窗口背景。
    _volumeChannel.invokeMethod('enableImmersive').catchError((_) {});
    _volumeChannel.setMethodCallHandler(_handleVolumeMethod);
    _updateVolumeIntercept();
    _beginSession();
  }

  @override
  void didUpdateWidget(NovelReaderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pathWord != widget.pathWord ||
        oldWidget.volumeId != widget.volumeId ||
        oldWidget.initialEntryIndex != widget.initialEntryIndex ||
        oldWidget.initialParagraphIndex != widget.initialParagraphIndex ||
        oldWidget.initialParagraphAlignment !=
            widget.initialParagraphAlignment ||
        oldWidget.resume != widget.resume ||
        oldWidget.preferDownloads != widget.preferDownloads ||
        oldWidget.highlightOnEntry != widget.highlightOnEntry ||
        oldWidget.source != widget.source) {
      // Capture against the old book's identity, not the new widget fields.
      unawaited(_flush());
      _beginSession();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_systemPadding == null) {
      _systemPadding = MediaQuery.paddingOf(context);
      // 先保存常规系统栏 inset，再同步首次进入的沉浸模式。
      _syncSystemUi();
    }
  }

  Future<void> _loadBookmarks() async {
    try {
      await _bookmarks.ensureLoaded();
      if (mounted) setState(() => _bookmarksLoaded = true);
    } catch (error, stack) {
      _warn(error, stack, 'bookmarks.load');
    }
  }

  void _onBookmarksChanged() {
    if (mounted) setState(() {});
  }

  void _onStatusSettingsChanged() {
    if (mounted) setState(() {});
  }

  // ── 阅读视图（滚动 / 翻页二选一）──

  bool get _paged => _settings.mode == NovelReaderMode.paged;

  /// 当前生效视图的位置快照；恢复中返回 null（由调用方回退到上次快照）。
  NovelReaderLocation? get _viewerLocation => _paged
      ? _pageViewKey.currentState?.currentLocation
      : _viewportKey.currentState?.currentLocation;

  /// 当前生效视图垂直中点处的段落（工具栏书签以此为准）。
  NovelReaderLocation? get _viewerCenter => _paged
      ? _pageViewKey.currentState?.anchorAtViewportCenter()
      : _viewportKey.currentState?.anchorAtViewportCenter();

  // ── 音量键翻页（仅翻页模式且开关开启时拦截）──

  Future<dynamic> _handleVolumeMethod(MethodCall call) async {
    if (!_settings.volumeKey || !_paged || _loading) return;
    if (call.method == 'volumeUp') {
      _pageViewKey.currentState?.prevPage();
    } else if (call.method == 'volumeDown') {
      _pageViewKey.currentState?.nextPage();
    }
  }

  void _updateVolumeIntercept() {
    unawaited(_setVolumeIntercept(_paged && _settings.volumeKey));
  }

  Future<void> _setVolumeIntercept(bool enabled) async {
    if (!_volumeChannelAvailable) return;
    try {
      await _volumeChannel.invokeMethod(enabled ? 'enable' : 'disable');
    } on MissingPluginException {
      // 桌面/测试环境没有音量键实现：静默降级，不再尝试。
      _volumeChannelAvailable = false;
    } on PlatformException catch (error) {
      debugPrint('Volume channel unavailable: $error');
      _volumeChannelAvailable = false;
    }
  }

  /// 工具栏显隐的唯一入口（正文点击 / 滚动 / 状态浮层）。与漫画阅读器一致：
  /// 显示时回到常规系统栏，隐藏时进入沉浸模式（状态栏与导航栏收起）。
  void _setToolbarVisible(bool visible) {
    if (_toolbarVisible == visible) return;
    setState(() => _toolbarVisible = visible);
    _syncSystemUi();
  }

  void _syncSystemUi() {
    if (_toolbarVisible) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  /// 工具栏显隐过渡：隐藏时滑出屏幕，并交回点击（隐藏态不拦正文手势）。
  /// 时长走 [adaptiveDuration]，开启「减少动画」时直接切换。
  Widget _slideOnToolbar(Widget child, {required bool fromTop}) {
    final visible = _toolbarVisible && !_settingsDragPreview;
    final hiddenOffset = _hiddenToolbarSlideOffset * (fromTop ? -1 : 1);
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: adaptiveDuration(context, const Duration(milliseconds: 200)),
        curve: adaptiveCurve(context, Curves.easeOutCubic),
        offset: Offset(0, visible ? 0 : hiddenOffset),
        child: child,
      ),
    );
  }

  /// 工具栏书签按钮的参照段落：视口垂直中点覆盖的段落（阅读习惯以
  /// 屏幕中间为基准），顶部首段仅在视口状态不可用时兜底。
  NovelReaderAnchor? get _bookmarkAnchor =>
      _viewerCenter?.anchor ?? _location?.anchor;

  /// 当前正在读的卷。连续阅读跨过接缝后正文属于下一卷，工具栏、
  /// 书签、目录与上/下一卷都要跟着它走。锚点自带卷 id 时直接采信，
  /// 避免回收旧卷后 item 下标短暂错位。
  String get _currentVolumeId {
    final located = (_viewerLocation ?? _location)?.anchor.volumeId ?? '';
    if (located.isNotEmpty) return located;
    final document = _document;
    if (document == null || document.itemCount == 0) return _volumeId;
    final item = (_location?.itemIndex ?? document.itemFor(_target)).clamp(
      0,
      document.itemCount - 1,
    );
    final volumeId = document.volumeIdForItem(item);
    return volumeId.isEmpty ? _volumeId : volumeId;
  }

  /// Current volume metadata, including volumes stitched in by continuous
  /// reading. Falls back to the entry detail before the first load completes.
  NovelVolumeDetail? get _currentVolumeDetail {
    final volumeId = _currentVolumeId;
    return _volumeDetails[volumeId] ??
        (_accessDetail?.volume.id == volumeId ? _accessDetail : null);
  }

  bool get _hasCurrentVolumeIllustrations =>
      _currentVolumeDetail?.volume.contents.any((entry) => entry.isImage) ??
      false;

  bool get _isBookmarked {
    final anchor = _bookmarkAnchor;
    return anchor != null &&
        _bookmarks.isBookmarked(
          pathWord: _pathWord,
          volumeId: anchor.volumeId.isEmpty ? _volumeId : anchor.volumeId,
          entryIndex: anchor.entryIndex,
          paragraphIndex: anchor.paragraphIndex,
        );
  }

  Future<void> _toggleBookmark() async {
    if (_loading || _bookmarking) return;
    final location = _viewerCenter ?? _viewerLocation;
    if (location == null || _content == null || _document == null) return;
    final progress = _progressAt(location, DateTime.now());
    final session = _session;
    setState(() => _bookmarking = true);
    try {
      final added = await _bookmarks.toggle(progress: progress);
      if (!mounted || !_active(session)) return;
      setState(() => _bookmarksLoaded = true);
      // 添加/取消书签都不弹提示：添加有段落闪光确认，取消时书签
      // 标记消失本身已可见。
      if (added) {
        _showHighlight(location.anchor);
      } else if (_isSameAnchor(_highlight, location.anchor)) {
        _clearHighlight();
      }
    } catch (error, stack) {
      _warn(error, stack, 'bookmarks.toggle');
      if (mounted && _active(session)) {
        showToast(
          context,
          AppLocalizations.of(
            context,
          )!.bookmarksUpdateFailedDetail(novelErrorMessage(error)),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _bookmarking = false);
    }
  }

  /// 闪光高亮一个段落（书签指向处）：淡入后保持，到期/滚动/跳转淡出。
  void _showHighlight(NovelReaderAnchor anchor) {
    _highlightTimer?.cancel();
    setState(() => _highlight = anchor);
    _startHighlightFade();
  }

  /// 长按菜单打开期间的段落选中态：同高亮卡片样式，但不自动过期，
  /// 随菜单关闭淡出。传 null 清除。
  void _selectParagraph(NovelReaderAnchor? anchor) {
    _highlightTimer?.cancel();
    if (anchor == null) {
      _clearHighlight();
      return;
    }
    setState(() => _highlight = anchor);
    _startHighlightFade(expire: false);
  }

  /// 启动一次高亮生命周期：淡入 → 保持 [_highlightDuration]。
  /// [expire] 为 false 时不安排自动清除（长按选中态由调用方控制）。
  void _startHighlightFade({bool expire = true}) {
    ++_highlightGen;
    final fade =
        _highlightFade ??
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 400),
        );
    if (prefersReducedMotion(context)) {
      fade.stop();
      fade.value = 1;
    } else {
      fade.forward(from: 0);
    }
    if (expire) {
      _highlightTimer = Timer(_highlightDuration, _clearHighlight);
    }
  }

  void _clearHighlight() {
    _highlightTimer?.cancel();
    if (_highlight == null) return;
    final fade = _highlightFade;
    final gen = ++_highlightGen;
    if (fade == null || prefersReducedMotion(context)) {
      fade?.stop();
      fade?.value = 0;
      setState(() => _highlight = null);
      return;
    }
    fade.reverse().whenCompleteOrCancel(() {
      // 淡出期间又打了新书签：旧淡出作废，新高亮不受影响。
      if (gen != _highlightGen) return;
      if (mounted && !_disposed && _highlight != null) {
        setState(() => _highlight = null);
      }
    });
  }

  /// 高亮锚点与某段落是否同一位置（连续阅读下卷 id 也参与判定）。
  bool _isSameAnchor(NovelReaderAnchor? a, NovelReaderAnchor b) =>
      a != null &&
      a.entryIndex == b.entryIndex &&
      a.paragraphIndex == b.paragraphIndex &&
      (a.volumeId.isEmpty || b.volumeId.isEmpty || a.volumeId == b.volumeId);

  void _beginSession() {
    final session = ++_session;
    ++_request;
    _pathWord = widget.pathWord;
    _volumeId = widget.volumeId;
    _source = widget.source ?? RepositoryNovelReaderSource(_repository);
    _fallbackName = widget.name;
    _fallbackCover = widget.cover;
    _loading = true;
    _content = null;
    _document = null;
    _accessDetail = null;
    _location = null;
    _pendingProgress = null;
    _error = null;
    _volumes = [];
    _volumesReady = false;
    _volumesLoad = null;
    _volumeDetails.clear();
    _highlightTimer?.cancel();
    _highlight = null;
    _saveTimer?.cancel();
    final initial = NovelReaderAnchor(
      entryIndex: widget.initialEntryIndex,
      paragraphIndex: widget.initialParagraphIndex,
      alignment: widget.initialParagraphAlignment,
    );
    _pendingEntryHighlight = widget.highlightOnEntry
        ? NovelReaderAnchor(
            entryIndex: initial.entryIndex,
            paragraphIndex: initial.paragraphIndex,
          )
        : null;
    unawaited(_initialize(session, widget.resume, initial));
  }

  bool _active(int session) => mounted && !_disposed && session == _session;

  Future<void> _initialize(
    int session,
    bool resume,
    NovelReaderAnchor initial,
  ) async {
    final path = _pathWord;
    final volume = _volumeId;
    final request = _request;
    var anchor = initial;
    try {
      final settings = await NovelReaderSettings.load();
      final fontFamily = await _loadContentFont(settings.fontFamily);
      if (!_active(session)) return;
      _settings = settings;
      _contentFontFamily = fontFamily;
      _setScreenOn(settings.keepScreenOn);
      _updateVolumeIntercept();
    } catch (error, stack) {
      _warn(error, stack, 'settings.load');
    }
    if (!_active(session)) return;
    if (resume) {
      try {
        final progress = await _store.readProgress(path);
        if (!_active(session) || request != _request) return;
        // Resume is deliberately scoped to the requested book AND volume.
        // Explicit navigation to a different volume must not be hijacked.
        if (progress != null &&
            progress.pathWord == path &&
            progress.volumeId == volume) {
          anchor = NovelReaderAnchor(
            entryIndex: progress.entryIndex,
            paragraphIndex: progress.paragraphIndex,
            alignment: progress.paragraphAlignment,
          );
          if (progress.updatedAt.isAfter(_lastTimestamp)) {
            _lastTimestamp = progress.updatedAt;
          }
        }
      } catch (error, stack) {
        _warn(error, stack, 'progress.load');
      }
    }
    if (!_active(session) || request != _request) return;
    if (widget.source == null) {
      final downloads = ref.read(novelDownloadStoreProvider);
      if (widget.preferDownloads) {
        try {
          await downloads.init();
        } catch (error, stack) {
          _warn(error, stack, 'downloads.resolve');
        }
      }
      if (!_active(session) || request != _request) return;
      _source = DownloadFirstNovelReaderSource(downloads, _source);
    }
    if (!_active(session) || request != _request) return;
    unawaited(_loadVolumes(session, path));
    await _loadVolume(volume, anchor: anchor);
  }

  Future<List<NovelVolume>> _ensureVolumes(int session, String path) {
    if (_volumesReady) return Future.value(_volumes);
    if (_volumesLoad case final pending?) return pending;
    final source = _source;
    final loading = source
        .loadVolumes(path)
        .then(
          (volumes) {
            if (_active(session)) {
              setState(() {
                _volumes = volumes;
                _volumesReady = true;
              });
            }
            return volumes;
          },
          onError: (Object error, StackTrace stack) {
            if (_active(session)) _volumesLoad = null;
            Error.throwWithStackTrace(error, stack);
          },
        );
    _volumesLoad = loading;
    return loading;
  }

  Future<void> _loadVolumes(int session, String path) async {
    try {
      await _ensureVolumes(session, path);
    } catch (error, stack) {
      if (_active(session)) _volumesLoad = null;
      // A missing remote directory must not prevent cached text from opening.
      _warn(error, stack, 'volumes.load');
    }
  }

  Future<void> _loadVolume(
    String volume, {
    required NovelReaderAnchor anchor,
    bool refresh = false,
    bool cachedOnly = false,
    bool lastEntry = false,
  }) async {
    unawaited(_flush());
    // 异常/空卷页为返回而展开的工具栏，重试时重新收起；正常换卷不重置。
    if (!_loading &&
        (_error != null || _document == null || _document!.itemCount == 0)) {
      _setToolbarVisible(false);
    }
    final session = _session;
    final request = ++_request;
    final path = _pathWord;
    setState(() {
      _volumeId = volume;
      _target = anchor;
      _loading = true;
      _content = null;
      _document = null;
      _location = null;
      _accessDetail = null;
      _error = null;
      _sliderValue = null;
      _offline = cachedOnly || _source.localOnly;
      _viewportKey = GlobalKey();
      _pageViewKey = GlobalKey();
      _highlightTimer?.cancel();
      _highlight = null;
      // 手动换卷是跳跃式跳转，不是连续下滑：卷栈重置为单卷。
      _stackVolumes.clear();
      _stackContents.clear();
      _stackLoads.clear();
      _stackPrefetches.clear();
      _stack = null;
      ++_contentRevision;
      _appending = false;
      _prepending = false;
      _seamError = null;
      _seamUnavailable = false;
      _headSeamError = null;
      _headSeamUnavailable = false;
    });
    try {
      final content = await _source.loadContent(
        path,
        volume,
        refresh: refresh,
        cachedOnly: cachedOnly,
      );
      if (!_active(session) || request != _request) return;
      if (content == null) {
        setState(() => _error = const _NoCachedVolume());
        return;
      }
      if (content.detail.isLocked) throw NovelAccessException(content.detail);
      await _prepareDialogueContent(content);
      if (!_active(session) || request != _request) return;
      _volumeDetails[volume] = content.detail;
      // 卷栈以当前卷起步；滚动模式下可原位追加下一卷 / 拼接上一卷。
      final stackVolume = NovelReaderVolumeDocument(
        volumeId: volume,
        volumeName: content.detail.volume.name,
        document: NovelReaderDocument(
          content.entries,
          ignoreBlankParagraphs: _settings.ignoreBlankParagraphs,
        ),
      );
      final stack = NovelReaderStack([stackVolume]);
      final document = stack;
      setState(() {
        _content = content;
        _stackVolumes
          ..clear()
          ..add(stackVolume);
        _stackContents
          ..clear()
          ..[volume] = content;
        _stack = stack;
        _document = document;
        _accessDetail = content.detail;
        if (document.itemCount > 0) {
          _target = lastEntry
              // 回翻到上一卷：落在文档末段（最后一页附近），而不是末章开头。
              ? document.anchorFor(document.itemCount - 1)
              : document.anchorFor(
                  document.itemFor(anchor),
                  alignment: anchor.alignment,
                );
        }
        // 书签进入的高亮：只在实际落点与书签段落一致时生效，避免
        // resume 等情况改写落点后高亮到别的段落。命中时把落点改为
        // 视口中部（阅读习惯），不再贴顶显示。
        final pending = _pendingEntryHighlight;
        _pendingEntryHighlight = null;
        if (pending != null &&
            document.itemCount > 0 &&
            pending.entryIndex == _target.entryIndex &&
            pending.paragraphIndex == _target.paragraphIndex) {
          _target = document.anchorFor(
            document.itemFor(pending),
            alignment: 0.5,
          );
          // 这里已处于 setState 内，直接改字段即可；动画启动交给
          // 帧回调，避免在同一次 build 里触发 vsync 断言。
          _highlight = pending;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_disposed && _highlight == pending) {
              _startHighlightFade();
            }
          });
        }
      });
    } catch (error, stack) {
      _warn(error, stack, 'volume.load');
      if (_active(session) && request == _request) {
        setState(() {
          _error = error;
          if (error is NovelAccessException) _accessDetail = error.detail;
        });
      }
    } finally {
      if (_active(session) && request == _request) {
        setState(() => _loading = false);
        if (_error != null || _document == null || _document!.itemCount == 0) {
          _setToolbarVisible(true);
        }
      }
    }
  }

  /// 进度按「当前正在读的卷」记录。连续阅读跨过接缝后，卷元数据跟着
  /// 段落所属卷走，进度条与恢复定位始终对应同一卷。
  NovelReadingProgress _progressAt(
    NovelReaderLocation location,
    DateTime updatedAt,
  ) {
    final document = _document!;
    final volumeId = document.volumeIdForItem(location.itemIndex);
    final content = _stackContents[volumeId] ?? _content!;
    final detail = content.detail;
    final book = detail.book;
    final volume = detail.volume;
    return NovelReadingProgress(
      pathWord: _pathWord,
      name: book.name.isEmpty ? _fallbackName : book.name,
      cover: book.cover.isEmpty ? _fallbackCover : book.cover,
      volumeId: volume.id.isEmpty ? _volumeId : volume.id,
      volumeName: volume.name,
      chapterName: document.paragraphAt(location.itemIndex).entry.name,
      entryIndex: location.anchor.entryIndex,
      paragraphIndex: location.anchor.paragraphIndex,
      paragraphAlignment: location.anchor.alignment,
      progress: location.progress,
      txtAddr: volume.txtAddr,
      updatedAt: updatedAt,
    );
  }

  void _recordLocation(
    NovelReaderLocation location, {
    bool rebuild = true,
    bool debounce = true,
  }) {
    final content = _content;
    final document = _document;
    if (_disposed || content == null || document == null || _loading) return;
    final previous = _location;
    _location = location;
    // 连续阅读时 entryIndex 会跨卷重复，卷 id 必须一起比较。
    final changed =
        previous == null ||
        previous.anchor.entryIndex != location.anchor.entryIndex ||
        previous.anchor.paragraphIndex != location.anchor.paragraphIndex ||
        previous.anchor.volumeId != location.anchor.volumeId ||
        (previous.anchor.alignment - location.anchor.alignment).abs() > 0.0001;
    if (!changed) return;
    final now = DateTime.now();
    _lastTimestamp = now.isAfter(_lastTimestamp)
        ? now
        : _lastTimestamp.add(const Duration(microseconds: 1));
    _pendingProgress = _progressAt(location, _lastTimestamp);
    if (debounce) {
      _saveTimer?.cancel();
      _saveTimer = Timer(
        const Duration(milliseconds: 350),
        () => unawaited(_flush()),
      );
    }
    if (rebuild &&
        mounted &&
        (previous == null ||
            previous.itemIndex != location.itemIndex ||
            (previous.progress * 100).round() !=
                (location.progress * 100).round())) {
      ++_locationRevision.value;
    }
  }

  /// Enqueue synchronously, before the route's returned Future is completed.
  /// The store serializes reads/writes; every operation owns an immutable book /
  /// volume snapshot, so slow saves never acquire a newer volume's metadata.
  Future<void> _flush() {
    _saveTimer?.cancel();
    final current = _viewerLocation;
    if (current != null) {
      _recordLocation(current, rebuild: false, debounce: false);
    }
    final progress = _pendingProgress;
    if (progress == null) return _lastWrite;
    _pendingProgress = null;
    final request = _request;
    _lastWrite = _store.saveProgress(progress).catchError((
      Object error,
      StackTrace stack,
    ) {
      _warn(error, stack, 'progress.save');
      // Retry on the next lifecycle/navigation flush, but never resurrect a
      // failed old-volume write after the reader has already moved elsewhere.
      if (!_disposed && request == _request && _pendingProgress == null) {
        _pendingProgress = progress;
      }
    });
    return _lastWrite;
  }

  void _onSliderValueChanged(double value) {
    setState(() => _sliderValue = value);
  }

  void _jumpTo(NovelReaderAnchor anchor) {
    final document = _document;
    if (document == null || document.itemCount == 0) return;
    unawaited(_flush());
    _clearHighlight();
    setState(() {
      _target = document.anchorFor(
        document.itemFor(anchor),
        alignment: anchor.alignment,
      );
      ++_jumpRevision;
      _sliderValue = null;
    });
  }

  String? _adjacentVolume(int direction) =>
      _adjacentVolumeOf(_currentVolumeId, direction);

  /// 供分片扩展方法更新界面（扩展方法不能直接调用受保护的 setState）。
  void _refresh(VoidCallback update) {
    if (mounted && !_disposed) setState(update);
  }

  bool _canStepVolume(int direction) =>
      !_loading && !_disposed && _adjacentVolume(direction) != null;

  /// 工具栏与翻页卷界都直接切换相邻卷，不做卷内章跳。
  /// 下一卷从首页开始，回翻上一卷落在末尾；卷内章节通过目录选择。
  void _stepVolume(int direction) {
    if (_loading || _disposed) return;
    final volume = _adjacentVolume(direction);
    if (volume == null) return;
    unawaited(
      _loadVolume(
        volume,
        anchor: NovelReaderAnchor(entryIndex: 0, volumeId: volume),
        lastEntry: direction < 0,
      ),
    );
  }

  /// 工具栏「插图」入口：直接打开当前卷插图，不关闭阅读页、不改进度。
  Future<void> _openIllustrations() async {
    final detail = _currentVolumeDetail;
    if (detail == null) return;
    final illustrations = detail.volume.contents
        .where((entry) => entry.isImage)
        .toList(growable: false);
    if (illustrations.isEmpty) return;
    await showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => NovelReaderIllustrations(
        volumeName: detail.volume.name,
        illustrations: illustrations,
        loadBytes: (url) =>
            _source.loadImageBytes(_pathWord, detail.volume.id, url),
      ),
    );
  }

  Future<void> _showContents() async {
    final session = _session;
    final current = _currentVolumeId;
    final selection = await showAppSheet<Object?>(
      context,
      heightFactor: 0.85,
      child: NovelReaderContentsSheet(
        repository: _repository,
        source: _source,
        pathWord: _pathWord,
        volumeId: current,
        entryIndex: _location?.anchor.entryIndex ?? _target.entryIndex,
        detail: _accessDetail,
        volumes: _volumesReady ? _volumes : null,
        loadVolumes: () => _ensureVolumes(session, _pathWord),
        volumeDetails: _volumeDetails,
        onDetailLoaded: (detail) {
          if (_active(session)) _volumeDetails[detail.volume.id] = detail;
        },
      ),
    );
    if (!_active(session) || selection == null) return;
    if (selection is NovelReaderCatalogExit) {
      await _exitToDetail();
      return;
    }
    if (selection case (final String volume, final int entry)) {
      if (volume == current && _document != null) {
        _jumpTo(NovelReaderAnchor(entryIndex: entry, volumeId: current));
      } else {
        await _loadVolume(
          volume,
          anchor: NovelReaderAnchor(entryIndex: entry, volumeId: volume),
        );
      }
    }
  }

  /// 「总目录」出口：目录抽屉的悬浮按钮统一收口到这里。
  /// 正常入口下详情页在栈底，pop 即可；无详情页直入时 pop 只会落回来源
  /// 列表页，不符「总目录」语义，改为原地替换成详情页（与漫画阅读器的
  /// _exitToCatalog 同一套规则）。
  Future<void> _exitToDetail() async {
    await _flush();
    if (!mounted) return;
    if (!widget.noDetailBelow) {
      await Navigator.of(context).maybePop();
      return;
    }
    // pushReplacementNamed 返回 void：路由替换同步生效，无需 await。
    context.pushReplacementNamed(
      AppRoutes.novelDetail,
      pathParameters: {'pathWord': _pathWord},
    );
  }

  Future<void> _prepareDialogueContent(NovelVolumeContent content) async {
    if (!_settings.dialogueEnabled) return;
    await novelDialogueCache.prepare(content.entries);
  }

  Future<String?> _loadContentFont(String selection) async {
    try {
      return await loadNovelReaderFont(selection);
    } catch (error, stack) {
      _warn(error, stack, 'font.load');
      if (mounted && !_disposed) {
        showToast(
          context,
          AppLocalizations.of(
            context,
          )!.appearanceFontLoadFailed(error.toString()),
          isError: true,
        );
      }
      return null;
    }
  }

  Future<void> _changeSettings(NovelReaderSettings settings) async {
    if (!mounted || _disposed) return;
    final revision = ++_settingsRevision;
    final session = _session;
    final fontFamily = settings.fontFamily == _settings.fontFamily
        ? _contentFontFamily
        : await _loadContentFont(settings.fontFamily);
    if (!_active(session) || revision != _settingsRevision) return;
    if (settings.dialogueEnabled && !_settings.dialogueEnabled) {
      int contentRevision;
      do {
        contentRevision = _contentRevision;
        await novelDialogueCache.prepare([
          for (final content in _stackContents.values) ...content.entries,
        ]);
        if (!_active(session) || revision != _settingsRevision) return;
      } while (contentRevision != _contentRevision);
    }
    unawaited(_flush());
    // 切换阅读模式：以当前位置为锚点，新视图接管后进度与落点连续。
    final anchor = settings.mode != _settings.mode
        ? (_viewerLocation?.anchor ?? _location?.anchor)
        : null;
    // 空行显隐改变文档形状：以当前位置为落点重建，锚点身份不变。
    // 连续阅读的卷栈逐卷重建，已追加的下一卷不会被丢掉。
    final reflow =
        settings.ignoreBlankParagraphs != _settings.ignoreBlankParagraphs;
    final current = _document;
    setState(() {
      _settings = settings;
      _contentFontFamily = fontFamily;
      if (anchor != null) _target = anchor;
      if (reflow &&
          _stackVolumes.isNotEmpty &&
          current != null &&
          current.itemCount > 0) {
        for (var index = 0; index < _stackVolumes.length; index++) {
          _stackVolumes[index] = _stackVolumes[index].rebuilt(
            ignoreBlankParagraphs: settings.ignoreBlankParagraphs,
          );
        }
        _stack = NovelReaderStack(List.of(_stackVolumes));
        _document = _stack;
        ++_contentRevision;
        // 文档形状变了，必须重新定位（与单纯追加下一卷区分开）。
        ++_jumpRevision;
        final base = anchor ?? _target;
        _target = _document!.anchorFor(
          _document!.itemFor(base),
          alignment: base.alignment,
        );
      }
    });
    _setScreenOn(settings.keepScreenOn);
    _updateVolumeIntercept();
    unawaited(
      settings.save().catchError((Object error, StackTrace stack) {
        _warn(error, stack, 'settings.save');
      }),
    );
  }

  Future<void> _showSettings() async {
    final dragPreview = ValueNotifier<bool>(false);
    void syncDragPreview() {
      if (!mounted || _settingsDragPreview == dragPreview.value) return;
      // 仅收起阅读 chrome，不切换系统栏，避免预览时屏幕尺寸变化。
      setState(() => _settingsDragPreview = dragPreview.value);
    }

    dragPreview.addListener(syncDragPreview);
    try {
      await showAppSheet<void>(
        context,
        maxHeightFactor: 0.7,
        barrierColor: Colors.transparent,
        fadeOutWhen: dragPreview,
        child: NovelReaderSettingsSheet(
          settings: _settings,
          fontFamily: _contentFontFamily,
          systemBrightness: MediaQuery.platformBrightnessOf(context),
          dragPreview: dragPreview,
          onChanged: _changeSettings,
        ),
      );
    } finally {
      dragPreview.removeListener(syncDragPreview);
      dragPreview.dispose();
      if (mounted && _settingsDragPreview) {
        setState(() => _settingsDragPreview = false);
      }
    }
  }

  /// 长按段落弹出的轻量上下文菜单：复制、书签。两种阅读模式同一手势
  /// （点按在翻页模式要翻页，双击识别会给单击引入延迟或先翻两页）。
  /// 菜单贴着落点弹出；书签 id 与按钮书签一致（同段落仅一个）。
  Future<void> _showParagraphMenu(
    NovelReaderParagraph paragraph,
    Offset position,
  ) async {
    final document = _document;
    if (document == null || _loading) return;
    final session = _session;
    final request = _request;
    final anchor = NovelReaderAnchor(
      entryIndex: paragraph.entry.entryIndex,
      paragraphIndex: paragraph.paragraphIndex,
      volumeId: paragraph.volumeId,
    );
    final bookmarked = _bookmarks.isBookmarked(
      pathWord: _pathWord,
      volumeId: paragraph.volumeId.isEmpty ? _volumeId : paragraph.volumeId,
      entryIndex: anchor.entryIndex,
      paragraphIndex: anchor.paragraphIndex,
    );
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()!
            as RenderBox;
    // 菜单打开期间给目标段落挂选中态（同书签高亮卡片，但由菜单生命
    // 周期控制）：长按到「操作哪个段落」一目了然。
    _selectParagraph(anchor);
    final action = await showMenu<_ParagraphAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(position, position.translate(0.01, 0.01)),
        Offset.zero & overlay.size,
      ),
      items: _paragraphMenuItems(paragraph, bookmarked),
    );
    final stillHere = _active(session) && request == _request;
    if (stillHere) _selectParagraph(null);
    if (!stillHere || action == null) return;
    switch (action) {
      case _ParagraphAction.copy:
        await Clipboard.setData(ClipboardData(text: paragraph.text));
        if (mounted && _active(session)) {
          showToast(
            context,
            AppLocalizations.of(context)!.chapterCommentsCopied,
          );
        }
      case _ParagraphAction.toggleBookmark:
        await _toggleParagraphBookmark(anchor);
    }
  }

  List<PopupMenuEntry<_ParagraphAction>> _paragraphMenuItems(
    NovelReaderParagraph paragraph,
    bool bookmarked,
  ) {
    final l10n = AppLocalizations.of(context)!;
    // 空行/空章节占位没有正文：复制无内容，也不允许打书签。
    final hasText = paragraph.text.trim().isNotEmpty;
    return [
      PopupMenuItem(
        value: _ParagraphAction.copy,
        enabled: hasText,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.copy_outlined),
            const SizedBox(width: AppSpacing.md),
            Text(l10n.copyButton),
          ],
        ),
      ),
      PopupMenuItem(
        value: _ParagraphAction.toggleBookmark,
        enabled: hasText,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 与阅读页书签按钮一致：书签色不随正文配色改变，已收藏
            // 状态由图标颜色表达，文案统一为「书签」。
            Icon(
              bookmarked ? Icons.bookmark : Icons.bookmark_border,
              color: bookmarked ? Colors.amberAccent : null,
            ),
            const SizedBox(width: AppSpacing.md),
            Text(l10n.novelReaderBookmark),
          ],
        ),
      ),
    ];
  }

  /// 对任意段落打/取消书签：进度取该段落在卷内的位置，对齐值用段首。
  /// 空行/空章节占位不接受书签（菜单项已禁用，这里再兜底）。
  Future<void> _toggleParagraphBookmark(NovelReaderAnchor anchor) async {
    final document = _document;
    if (_bookmarking || document == null || document.itemCount == 0) return;
    if (document.paragraphAt(document.itemFor(anchor)).text.trim().isEmpty) {
      return;
    }
    final item = document.itemFor(anchor);
    final location = NovelReaderLocation(
      anchor: anchor,
      itemIndex: item,
      // 段落书签落在段首：进度按该段落在所属卷内的位置计算。
      progress: document.progressAt(item, 0),
    );
    final session = _session;
    setState(() => _bookmarking = true);
    try {
      final added = await _bookmarks.toggle(
        progress: _progressAt(location, DateTime.now()),
      );
      if (!mounted || !_active(session)) return;
      setState(() => _bookmarksLoaded = true);
      if (added) {
        _showHighlight(anchor);
      } else if (_isSameAnchor(_highlight, anchor)) {
        _clearHighlight();
      }
    } catch (error, stack) {
      _warn(error, stack, 'bookmarks.toggle');
      if (mounted && _active(session)) {
        showToast(
          context,
          AppLocalizations.of(
            context,
          )!.bookmarksUpdateFailedDetail(novelErrorMessage(error)),
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _bookmarking = false);
    }
  }

  void _setScreenOn(bool enabled) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final shouldEnable =
        enabled &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
    Future<void> toggle() async {
      try {
        await WakelockPlus.toggle(enable: shouldEnable);
      } catch (error, stack) {
        // Desktop/tests may not provide this plugin. Reading must still work.
        _warn(error, stack, 'screen_on');
      }
    }

    final operation = _wakeQueue?.then((_) => toggle()) ?? toggle();
    late final Future<void> tail;
    tail = operation.whenComplete(() {
      if (identical(_wakeQueue, tail)) _wakeQueue = null;
    });
    _wakeQueue = tail;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_flush());
      _setScreenOn(false);
    } else if (state == AppLifecycleState.resumed) {
      _setScreenOn(_settings.keepScreenOn);
    }
  }

  Future<void> _back() async {
    await _flush();
    if (mounted) await Navigator.of(context).maybePop();
  }

  Future<void> _login() async {
    final session = _session;
    final request = _request;
    await context.pushNamed(
      AppRoutes.login,
      queryParameters: {'copyOnly': 'true'},
    );
    if (_active(session) && request == _request) {
      await _loadVolume(_volumeId, anchor: _target, refresh: true);
    }
  }

  void _warn(Object error, StackTrace stack, String action) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'novel_reader.$action',
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_flush());
    _disposed = true;
    ++_session;
    ++_request;
    _saveTimer?.cancel();
    _locationRevision.dispose();
    _highlightTimer?.cancel();
    _highlightFade?.dispose();
    _bookmarks.removeListener(_onBookmarksChanged);
    _statusSettings.removeListener(_onStatusSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _setScreenOn(false);
    // 沉浸模式是页面级状态，离开时恢复常规系统栏（与漫画阅读器一致）。
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    unawaited(_setVolumeIntercept(false));
    _volumeChannel.setMethodCallHandler(null);
    // 恢复默认的刘海区避让模式。
    _volumeChannel.invokeMethod('disableImmersive').catchError((_) {});
    super.dispose();
  }

  ThemeData _themeForPalette(NovelReaderPalette palette) {
    final base = Theme.of(context);
    final cached = _readerTheme;
    if (cached != null &&
        _readerThemeBase == base &&
        _readerThemePalette?.background == palette.background &&
        _readerThemePalette?.foreground == palette.foreground) {
      return cached;
    }
    _readerThemeBase = base;
    _readerThemePalette = palette;
    return _readerTheme = palette.applyTo(base);
  }

  @override
  Widget build(BuildContext context) {
    // 阅读纸张固定跟随系统亮暗选择配色方案，不受 App 强制主题影响。
    final palette = NovelReaderPalette.resolve(
      _settings,
      MediaQuery.platformBrightnessOf(context),
    );
    final document = _document;
    final reading =
        !_loading &&
        _error == null &&
        document != null &&
        document.itemCount > 0;
    // 隐藏的工具栏复用 child；位置变化只更新可见的阅读 chrome。
    final header = ValueListenableBuilder<int>(
      valueListenable: _locationRevision,
      child: _toolbarVisible ? null : _buildHeader(),
      builder: (context, revision, child) => child ?? _buildHeader(),
    );
    final body = _buildBody();
    final toolbar = ValueListenableBuilder<int>(
      valueListenable: _locationRevision,
      child: _toolbarVisible ? null : _buildToolbar(),
      builder: (context, revision, child) => child ?? _buildToolbar(),
    );
    return Theme(
      data: _themeForPalette(palette),
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) unawaited(_flush());
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          // 工具栏固定黑底白字，系统栏保持浅色图标。
          value: _toolbarVisible
              ? ReaderChrome.systemUiToolbar
              : ReaderChrome.systemUiImmersive,
          child: Scaffold(
            backgroundColor: palette.background,
            body: reading
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // 正文 viewport 铺满全屏（纸张延伸到屏幕顶/底，与漫画
                      // 一致）：安全区 inset 经 contentPadding 交给列表内容
                      // 层，viewport 尺寸恒定，不会触发 anchor restoration。
                      body,
                      // 默认遮罩压暗状态组件；开启「不遮挡状态组件」后
                      // 将浮层画在遮罩上方，显隐与点按规则保持不变。
                      if (_statusSettings.statusOverlay &&
                          !_settings.focusKeepStatusVisible)
                        _buildStatusOverlay(),
                      NovelFocusMask(
                        key: const ValueKey('novel-focus-mask-widget'),
                        enabled: _settings.focusModeEnabled,
                        topRatio: _settings.focusTopRatio,
                        bottomRatio: _settings.focusBottomRatio,
                        opacity: _settings.focusOpacity,
                      ),
                      if (_statusSettings.statusOverlay &&
                          _settings.focusKeepStatusVisible)
                        _buildStatusOverlay(),
                      // 显隐都留在树里做滑动过渡（与漫画阅读器同一套规则）。
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _slideOnToolbar(header, fromTop: true),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: _slideOnToolbar(toolbar, fromTop: false),
                      ),
                    ],
                  )
                // Loading / retry actions remain outside the chrome so they
                // are reachable even in a short viewport with large text.
                : Column(
                    children: [
                      // chrome 自带 SafeArea，黑色底板必须覆盖系统栏区域。
                      if (_toolbarVisible) header,
                      Expanded(child: SafeArea(child: body)),
                      if (_toolbarVisible) toolbar,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _NoCachedVolume {
  const _NoCachedVolume();
}

/// 长按段落菜单的动作。
enum _ParagraphAction { copy, toggleBookmark }
