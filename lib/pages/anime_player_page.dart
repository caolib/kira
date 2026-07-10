import 'dart:async';

import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material3_expressive_loading_indicator/material3_expressive_loading_indicator.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api/api_client.dart';
import '../api/dandanplay_api.dart';
import '../l10n/app_localizations.dart';
import '../models/anime.dart';
import '../models/user_manager.dart';
import '../routing/app_router.dart';
import '../utils/anime_download_manager.dart';
import '../utils/anime_playback_history.dart';
import '../utils/app_dio.dart';
import '../utils/app_logger.dart';
import '../utils/chinese_converter.dart';
import '../utils/network_error.dart';

part 'anime_player/chapter_selector.dart';
part 'anime_player/danmaku_panels.dart';
part 'anime_player/error_panel.dart';
part 'anime_player/media_open_diagnosis.dart';
part 'anime_player/player_controls.dart';
part 'anime_player/player_settings_panel.dart';
part 'anime_player/video_link_panel.dart';

class AnimePlayerPage extends StatefulWidget {
  final String animeName;
  final String pathWord;
  final String chapterUuid;
  final String chapterName;
  final String line;
  final List<AnimeChapter> chapters;
  final String? localVideoPath;

  const AnimePlayerPage({
    super.key,
    required this.animeName,
    required this.pathWord,
    required this.chapterUuid,
    required this.chapterName,
    required this.line,
    this.chapters = const [],
    this.localVideoPath,
  });

  @override
  State<AnimePlayerPage> createState() => _AnimePlayerPageState();
}

class _AnimePlayerPageState extends State<AnimePlayerPage>
    with WidgetsBindingObserver {
  static const _videoUserAgent =
      'Mozilla/5.0 (Linux; Android 12; 23117RK66C Build/V417IR; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/110.0.5481.154 Mobile Safari/537.36';
  static const _maxPlayerLogLines = 24;
  static const _playbackProgressSaveInterval = Duration(seconds: 5);
  static const _minPlaybackProgressToSave = Duration(seconds: 3);
  static const _playbackProgressSeekTolerance = Duration(seconds: 2);

  final _api = ApiClient();
  final _user = UserManager();
  final _downloads = AnimeDownloadManager();
  late final Player _player = Player(
    configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn),
  );
  late final VideoController _videoController = VideoController(_player);
  AnimePlayback? _playback;
  late String _currentChapterUuid;
  late String _currentChapterName;
  late String _line;
  String? _videoUrl;
  bool _loading = true;
  bool _buffering = false;
  bool _requiresLogin = false;
  int _openMediaSerial = 0;
  String? _error;
  String? _rawError;
  final List<String> _recentPlayerLogs = <String>[];
  bool _readyToSavePlaybackProgress = false;
  DateTime? _lastPlaybackProgressSavedAt;
  AnimePlaybackRecord? _playbackRecord;
  bool _playbackProgressRestored = false;

  DanmakuController? _danmakuController;
  Map<int, List<DanmakuContentItem>> _danmakuItems = {};
  int _lastDanmakuSec = -1;
  int _danmakuSurfaceGeneration = 0;
  bool _danmakuVisible = true;

  // 内联搜索
  List<String> _searchSegments = [];
  Set<int> _selectedSegmentIndices = {};
  final _searchController = TextEditingController();
  List<DandanplayEpisode> _inlineResults = [];
  bool _inlineSearching = false;
  bool _hasSearched = false;
  int? _selectedDanmakuEpisodeId;
  int? _loadingDanmakuEpisodeId;
  int _danmakuLoadSerial = 0;
  int _danmakuSearchCollapseRevision = 0;
  bool _danmakuSearchCollapsedByBinding = false;
  bool _initialLoadStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentChapterUuid = widget.chapterUuid;
    _currentChapterName = widget.chapterName;
    _line = widget.line;
    _danmakuVisible = _user.danmakuEnabled;

    _player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (playing) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
      if (playing && _danmakuVisible) {
        _danmakuController?.resume();
      } else {
        _danmakuController?.pause();
      }
    });

    _player.stream.position.listen((position) {
      if (!mounted) return;
      _maybeSavePlaybackProgress(position);
      if (_player.state.playing && _danmakuVisible) {
        final sec = position.inSeconds;
        if (sec != _lastDanmakuSec) {
          if ((sec - _lastDanmakuSec).abs() > 2) {
            _danmakuController?.clear();
          }
          _lastDanmakuSec = sec;
          if (_danmakuItems.containsKey(sec)) {
            for (final item in _danmakuItems[sec]!) {
              _danmakuController?.addDanmaku(item);
            }
          }
        }
      }
    });

    _player.stream.buffering.listen((buffering) {
      if (!mounted) return;
      setState(() => _buffering = buffering);
    });

    _player.stream.log.listen(_rememberPlayerLog);
    _player.stream.error.listen((error) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      _recordPlayerError(error);
      setState(() {
        _error = _formatPlayerError(error, l10n: l10n);
        _rawError = _buildPlayerDebugReport(error, l10n: l10n);
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialLoadStarted) return;
    _initialLoadStarted = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_savePlaybackProgress(force: true, updateState: false));
    _openMediaSerial++;
    _player.dispose();
    WakelockPlus.disable();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      unawaited(_savePlaybackProgress(force: true, updateState: false));
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final l10n = AppLocalizations.of(context)!;
    _readyToSavePlaybackProgress = false;
    _lastPlaybackProgressSavedAt = null;
    _playbackProgressRestored = false;
    final danmakuSerial = ++_danmakuLoadSerial;
    setState(() {
      _loading = true;
      _buffering = false;
      _requiresLogin = false;
      _error = null;
      _videoUrl = null;
      _danmakuItems = {};
      _selectedDanmakuEpisodeId = null;
      _loadingDanmakuEpisodeId = null;
      _playbackRecord = null;
      _danmakuSearchCollapsedByBinding = false;
    });
    unawaited(_loadPlaybackRecord(danmakuSerial));

    if (widget.localVideoPath != null) {
      if (!mounted) return;
      setState(() {
        _videoUrl = widget.localVideoPath;
        _loading = false;
        _buffering = true;
      });
      unawaited(_openMedia(widget.localVideoPath!));
      unawaited(_loadSavedDanmakuOrSetupSearch(danmakuSerial));
      return;
    }

    await _downloads.init();
    final localPath = _downloads.getLocalVideoPath(
      widget.pathWord,
      _currentChapterUuid,
    );
    if (localPath != null) {
      if (!mounted) return;
      setState(() {
        _videoUrl = localPath;
        _loading = false;
        _buffering = true;
      });
      unawaited(_openMedia(localPath));
      unawaited(_loadSavedDanmakuOrSetupSearch(danmakuSerial));
      return;
    }

    if (!_user.isLoggedIn) {
      setState(() {
        _loading = false;
        _requiresLogin = true;
        _error = l10n.animePlayerLoginRequiredToPlay;
      });
      return;
    }

    try {
      final playback = await _getPlayback(forceRefresh: forceRefresh);
      final videoUrl = _resolveVideoUrl(playback.chapter);
      if (videoUrl.isEmpty) {
        throw StateError(l10n.animePlayerEmptyVideoUrl);
      }

      if (!mounted) return;
      setState(() {
        _playback = playback;
        _currentChapterName = playback.chapter.name.isNotEmpty
            ? playback.chapter.name
            : _currentChapterName;
        _videoUrl = videoUrl;
        _loading = false;
        _buffering = true;
      });
      unawaited(_openMedia(videoUrl));
      unawaited(_loadSavedDanmakuOrSetupSearch(danmakuSerial));
    } catch (e) {
      debugPrint('AnimePlayerPage load error: $e');
      if (!mounted) return;
      final requiresLogin = _isUnauthorized(e);
      if (requiresLogin) {
        await _user.logout();
        if (!mounted) return;
      }
      setState(() {
        _loading = false;
        _requiresLogin = requiresLogin;
        _error = requiresLogin
            ? l10n.animePlayerLoginRequiredToPlay
            : _formatLoadError(e, l10n);
        _rawError = e.toString();
      });
    }
  }

  bool _isUnauthorized(Object error) =>
      error is DioException && error.response?.statusCode == 401;

  String _formatLoadError(Object error, AppLocalizations l10n) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final message =
            data['message']?.toString() ??
            (data['results'] is Map
                ? data['results']['detail']?.toString()
                : null);
        if (message != null && message.isNotEmpty) return message;
      }
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return l10n.animePlayerRequestFailedStatus(statusCode);
      }
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;
    }
    return error.toString();
  }

  void _rememberPlayerLog(PlayerLog log) {
    final line = '[${log.level}] ${log.prefix}: ${log.text}';
    if (_recentPlayerLogs.isNotEmpty && _recentPlayerLogs.last == line) return;
    _recentPlayerLogs.add(line);
    if (_recentPlayerLogs.length > _maxPlayerLogLines) {
      _recentPlayerLogs.removeRange(
        0,
        _recentPlayerLogs.length - _maxPlayerLogLines,
      );
    }
    debugPrint('AnimePlayerPage player log: $line');
  }

  String _buildPlayerDebugReport(
    String message, {
    _MediaOpenDiagnosis? diagnosis,
    required AppLocalizations l10n,
  }) {
    final buffer = StringBuffer()..writeln(message);
    if (_recentPlayerLogs.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(l10n.animePlayerMpvLogTitle);
      for (final line in _recentPlayerLogs) {
        buffer.writeln(line);
      }
    }
    final diagnosisText = diagnosis?.toDebugString(l10n);
    if (diagnosisText != null && diagnosisText.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(l10n.animePlayerQuickDiagnosisTitle)
        ..writeln(diagnosisText);
    }
    return buffer.toString().trim();
  }

  String _formatPlayerError(
    String message, {
    _MediaOpenDiagnosis? diagnosis,
    required AppLocalizations l10n,
  }) {
    final lower = message.toLowerCase();
    final manifestStatus = diagnosis?.manifestStatus;
    final segmentStatus = diagnosis?.segmentStatus;
    if (lower.contains('403') ||
        lower.contains('forbidden') ||
        manifestStatus == 403 ||
        segmentStatus == 403) {
      return l10n.animePlayerSourceForbidden;
    }
    if (lower.contains('404') ||
        lower.contains('not found') ||
        manifestStatus == 404 ||
        segmentStatus == 404) {
      return l10n.animePlayerSourceNotFound;
    }
    if (lower.contains('certificate') ||
        lower.contains('tls') ||
        lower.contains('ssl')) {
      return l10n.animePlayerCertificateFailed;
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return l10n.animePlayerConnectionTimeout;
    }
    if (diagnosis?.networkLooksHealthy == true) {
      return l10n.animePlayerCannotParseStream;
    }
    if (lower.contains('127.0.0.1') ||
        lower.contains('localhost') ||
        lower.contains('failed to open')) {
      return l10n.animePlayerEnableProxyToRetry;
    }
    return message;
  }

  Future<_MediaOpenDiagnosis> _diagnoseMediaOpen(String videoUrl) async {
    final l10n = AppLocalizations.of(context)!;
    final uri = Uri.tryParse(videoUrl);
    if (uri == null || !uri.hasScheme) {
      return _MediaOpenDiagnosis(
        manifestError: l10n.animePlayerInvalidVideoUri,
      );
    }

    final dio = AppDio.create(
      source: 'anime_player',
      options: BaseOptions(
        headers: _videoHttpHeaders,
        responseType: ResponseType.plain,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    try {
      final manifestResponse = await dio.getUri<String>(uri);
      await _recordPlaybackHttpFailureIfNeeded(
        manifestResponse,
        message: l10n.animePlayerDiagnosisRequestFailed,
      );
      final manifestText = manifestResponse.data ?? '';
      final manifestLooksLikeHls = manifestText.contains('#EXTM3U');
      final firstSegment = manifestLooksLikeHls
          ? manifestText
                .split(RegExp(r'\r?\n'))
                .map((line) => line.trim())
                .firstWhere(
                  (line) => line.isNotEmpty && !line.startsWith('#'),
                  orElse: () => '',
                )
          : '';
      final segmentUri = firstSegment.isEmpty
          ? null
          : uri.resolve(firstSegment);

      int? segmentStatus;
      int? segmentBytes;
      String? segmentError;
      if (segmentUri != null) {
        try {
          final segmentResponse = await dio.getUri<List<int>>(
            segmentUri,
            options: Options(responseType: ResponseType.bytes),
          );
          await _recordPlaybackHttpFailureIfNeeded(
            segmentResponse,
            message: l10n.animePlayerSegmentDiagnosisRequestFailed,
          );
          segmentStatus = segmentResponse.statusCode;
          segmentBytes = segmentResponse.data?.length;
        } on DioException catch (e) {
          segmentStatus = e.response?.statusCode;
          segmentError = _formatLoadError(e, l10n);
        }
      }

      return _MediaOpenDiagnosis(
        manifestStatus: manifestResponse.statusCode,
        manifestLooksLikeHls: manifestLooksLikeHls,
        manifestError: manifestResponse.statusCode == 200
            ? null
            : l10n.animePlayerRequestFailedStatusText(
                (manifestResponse.statusCode ?? 'unknown').toString(),
              ),
        firstSegmentUrl: segmentUri?.toString(),
        segmentStatus: segmentStatus,
        segmentBytes: segmentBytes,
        segmentError:
            segmentError ??
            (segmentUri == null ? l10n.animePlayerSegmentUrlNotResolved : null),
      );
    } on DioException catch (e) {
      return _MediaOpenDiagnosis(
        manifestStatus: e.response?.statusCode,
        manifestError: _formatLoadError(e, l10n),
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<void> _enrichOpenMediaFailure({
    required int serial,
    required String videoUrl,
    required String rawMessage,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final diagnosis = await _diagnoseMediaOpen(videoUrl);
    if (!mounted || serial != _openMediaSerial) return;
    _recordPlayerError(rawMessage, diagnosis: diagnosis);
    setState(() {
      _error = _formatPlayerError(rawMessage, diagnosis: diagnosis, l10n: l10n);
      _rawError = _buildPlayerDebugReport(
        rawMessage,
        diagnosis: diagnosis,
        l10n: l10n,
      );
    });
  }

  Future<void> _recordPlaybackHttpFailureIfNeeded(
    Response<dynamic> response, {
    required String message,
  }) async {
    if (response.statusCode == 200) return;
    await NetworkError.recordDioResponse(
      response,
      source: 'anime_player',
      level: _httpLogLevel(response.statusCode),
      message: message,
    );
  }

  AppLogLevel _httpLogLevel(int? statusCode) {
    if (statusCode != null && statusCode >= 500) return AppLogLevel.error;
    return AppLogLevel.warning;
  }

  void _recordPlayerError(String message, {_MediaOpenDiagnosis? diagnosis}) {
    final l10n = AppLocalizations.of(context)!;
    unawaited(
      AppLogger.instance.recordError(
        message,
        source: 'anime_player',
        context: {
          'pathWord': widget.pathWord,
          'chapterUuid': _currentChapterUuid,
          'chapterName': _currentChapterName,
          'line': _line,
          if (_videoUrl != null && _videoUrl!.isNotEmpty) 'videoUrl': _videoUrl,
          if (_recentPlayerLogs.isNotEmpty)
            'playerLogs': _recentPlayerLogs.join('\n'),
          if (diagnosis != null) 'diagnosis': diagnosis.toDebugString(l10n),
        },
      ),
    );
  }

  Future<void> _goLogin() async {
    final loggedIn = await context.pushNamed<bool>(AppRoutes.login);
    if (loggedIn == true && mounted) {
      await _load();
    }
  }

  Future<AnimePlayback> _getPlayback({required bool forceRefresh}) async {
    return _api.anime.getAnimePlayback(
      widget.pathWord,
      _currentChapterUuid,
      line: _line,
      forceRefresh: forceRefresh,
    );
  }

  Future<void> _refreshPlayback() async {
    if (_loading) return;
    await _load(forceRefresh: true);
  }

  void _showPlayerHint(String message, {bool isError = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final bg = isError ? cs.errorContainer : cs.inverseSurface;
    final fg = isError ? cs.onErrorContainer : cs.onInverseSurface;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          elevation: 3,
          duration: const Duration(milliseconds: 1600),
          backgroundColor: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _openMedia(String videoUrl) async {
    final serial = ++_openMediaSerial;
    _recentPlayerLogs.clear();
    _readyToSavePlaybackProgress = false;
    _lastPlaybackProgressSavedAt = null;
    if (mounted) {
      setState(() {
        _buffering = true;
        _error = null;
        _rawError = null;
      });
    }

    try {
      await _player.open(Media(videoUrl, httpHeaders: _videoHttpHeaders));
      if (!mounted || serial != _openMediaSerial) return;
      _readyToSavePlaybackProgress = true;
      setState(() {
        _buffering = false;
        _error = null;
        _rawError = null;
      });
      unawaited(_restorePlaybackProgress(serial));
    } catch (e) {
      debugPrint('AnimePlayerPage open media error: $e');
      final rawMessage = e.toString();
      if (!mounted || serial != _openMediaSerial) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _buffering = false;
        _error = _formatPlayerError(rawMessage, l10n: l10n);
        _rawError = _buildPlayerDebugReport(rawMessage, l10n: l10n);
      });
      unawaited(
        _enrichOpenMediaFailure(
          serial: serial,
          videoUrl: videoUrl,
          rawMessage: rawMessage,
        ),
      );
    }
  }

  static const _videoHttpHeaders = {
    'User-Agent': _videoUserAgent,
    'Connection': 'Keep-Alive',
    'Accept-Encoding': 'gzip',
  };

  String _resolveVideoUrl(AnimePlaybackChapter chapter) {
    if (chapter.video.isNotEmpty) return chapter.video;
    for (final url in chapter.videoList) {
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  bool get _canUsePlaybackHistory =>
      _user.animePlaybackProgressEnabled &&
      widget.pathWord.trim().isNotEmpty &&
      _currentChapterUuid.trim().isNotEmpty;

  bool _isRestorablePlaybackRecord(AnimePlaybackRecord? record) {
    if (!_canUsePlaybackHistory || record == null) return false;
    final position = record.position;
    if (position < _minPlaybackProgressToSave) return false;
    final duration = record.duration;
    if (duration > Duration.zero) {
      if (position >= duration) return false;
      if (duration - position <= const Duration(seconds: 5)) return false;
    }
    return true;
  }

  Future<AnimePlaybackRecord?> _loadPlaybackRecord(int serial) async {
    if (!_canUsePlaybackHistory) return null;
    final record = await AnimePlaybackHistory.get(
      pathWord: widget.pathWord,
      chapterUuid: _currentChapterUuid,
    );
    if (!mounted || serial != _danmakuLoadSerial) return record;
    setState(() => _playbackRecord = record);
    return record;
  }

  Future<void> _restorePlaybackProgress(int serial) async {
    if (!_canUsePlaybackHistory) return;
    final record =
        _playbackRecord ?? await _loadPlaybackRecord(_danmakuLoadSerial);
    if (!mounted || serial != _openMediaSerial || !_canUsePlaybackHistory) {
      return;
    }

    if (!_isRestorablePlaybackRecord(record)) return;

    await _waitForPlaybackBeforeRestore(serial);
    if (!mounted || serial != _openMediaSerial) return;

    final restored = await _seekToPlaybackProgress(record!.position, serial);
    if (!mounted || serial != _openMediaSerial) return;
    if (!restored) return;

    _lastDanmakuSec = -1;
    _playbackProgressRestored = true;
    setState(() {});
  }

  Future<void> _waitForPlaybackBeforeRestore(int serial) async {
    for (var i = 0; i < 20; i++) {
      if (!mounted || serial != _openMediaSerial) return;
      if (_player.state.playing) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<bool> _seekToPlaybackProgress(Duration position, int serial) async {
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!mounted || serial != _openMediaSerial) return false;
      final duration = _player.state.duration;
      if (duration > Duration.zero &&
          (position >= duration ||
              duration - position <= const Duration(seconds: 5))) {
        return false;
      }

      try {
        await _player.seek(position);
      } catch (e) {
        debugPrint('Restore playback progress seek error: $e');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || serial != _openMediaSerial) return false;

      final current = _player.state.position;
      if (!_isNearOrAfterPlaybackProgress(current, position)) {
        continue;
      }

      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (!mounted || serial != _openMediaSerial) return false;
      if (_isNearOrAfterPlaybackProgress(_player.state.position, position)) {
        return true;
      }
    }

    try {
      await _player.seek(position);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      return mounted &&
          serial == _openMediaSerial &&
          _isNearOrAfterPlaybackProgress(_player.state.position, position);
    } catch (e) {
      debugPrint('Restore playback progress final seek error: $e');
      return false;
    }
  }

  bool _isNearOrAfterPlaybackProgress(Duration current, Duration target) {
    return current + _playbackProgressSeekTolerance >= target;
  }

  void _maybeSavePlaybackProgress(Duration position) {
    if (!_readyToSavePlaybackProgress) return;
    final record = _playbackRecord;
    if (!_playbackProgressRestored &&
        _isRestorablePlaybackRecord(record) &&
        position + _playbackProgressSeekTolerance < record!.position) {
      return;
    }
    final lastSavedAt = _lastPlaybackProgressSavedAt;
    final now = DateTime.now();
    if (lastSavedAt != null &&
        now.difference(lastSavedAt) < _playbackProgressSaveInterval) {
      return;
    }
    _lastPlaybackProgressSavedAt = now;
    unawaited(_savePlaybackProgress(position: position));
  }

  Future<void> _savePlaybackProgress({
    Duration? position,
    bool force = false,
    bool updateState = true,
  }) async {
    if (!_canUsePlaybackHistory) return;
    if (!_readyToSavePlaybackProgress && !force) return;

    final currentPosition = position ?? _player.state.position;
    final duration = _player.state.duration;
    if (currentPosition < _minPlaybackProgressToSave) return;
    final existingRecord = _playbackRecord;
    if (!_playbackProgressRestored &&
        _isRestorablePlaybackRecord(existingRecord) &&
        currentPosition + _playbackProgressSeekTolerance <
            existingRecord!.position) {
      return;
    }
    final targetChapterUuid = _currentChapterUuid;
    final targetChapterName = _currentChapterName;

    var progressPosition = currentPosition;
    if (duration > Duration.zero &&
        duration - currentPosition <= const Duration(seconds: 5)) {
      progressPosition = Duration.zero;
    }

    await AnimePlaybackHistory.saveProgress(
      pathWord: widget.pathWord,
      chapterUuid: _currentChapterUuid,
      chapterName: _currentChapterName,
      position: progressPosition,
      duration: duration,
    );
    if (!updateState || !mounted || targetChapterUuid != _currentChapterUuid) {
      return;
    }
    setState(() {
      _playbackRecord = AnimePlaybackRecord(
        chapterUuid: targetChapterUuid,
        chapterName: targetChapterName,
        position: progressPosition,
        duration: duration,
        danmakuEpisodeId: _playbackRecord?.danmakuEpisodeId,
        updatedAt: DateTime.now(),
      );
    });
  }

  String _removeParentheses(String text) =>
      text.replaceAll(RegExp(r'\([^)]*\)'), '').trim();

  Future<void> _switchLine(String line) async {
    if (line == _line || _loading) return;
    await _savePlaybackProgress(force: true, updateState: false);
    if (!mounted) return;
    setState(() => _line = line);
    await _load();
  }

  Future<void> _openChapter(AnimeChapter chapter) async {
    final l10n = AppLocalizations.of(context)!;
    if (chapter.uuid == _currentChapterUuid) return;
    if (_loading) {
      _showPlayerHint(
        AppLocalizations.of(context)!.animePlayerLoadingCannotSwitch,
        isError: true,
      );
      return;
    }
    final line = _resolveChapterLine(chapter) ?? _line;
    if (line.isEmpty) {
      _showPlayerHint(l10n.animeDetailNoAvailableLine, isError: true);
      return;
    }

    await _savePlaybackProgress(force: true, updateState: false);
    if (!mounted) return;
    setState(() {
      _currentChapterUuid = chapter.uuid;
      _currentChapterName = chapter.name;
      _line = line;
    });
    await _load();
  }

  String? _resolveChapterLine(AnimeChapter chapter) {
    for (final line in chapter.lines) {
      if (line.config && line.pathWord.isNotEmpty) return line.pathWord;
    }
    for (final line in chapter.lines) {
      if (line.pathWord.isNotEmpty) return line.pathWord;
    }
    return null;
  }

  Future<void> _copyVideoUrl() async {
    final url = _videoUrl;
    if (url == null || url.isEmpty) {
      _showPlayerHint(
        AppLocalizations.of(context)!.animePlayerNoVideoUrlToCopy,
        isError: true,
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    _showPlayerHint(AppLocalizations.of(context)!.animePlayerVideoUrlCopied);
  }

  Future<void> _openVideoUrl() async {
    final url = _videoUrl;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      _showPlayerHint(
        AppLocalizations.of(context)!.animePlayerNoVideoUrlToOpen,
        isError: true,
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      _showPlayerHint(
        AppLocalizations.of(context)!.animePlayerOpenVideoUrlFailed,
        isError: true,
      );
    }
  }

  String get _title => _playback?.chapter.name.isNotEmpty == true
      ? _playback!.chapter.name
      : _currentChapterName;

  void _skipForward() {
    final duration = _player.state.duration;
    final position = _player.state.position;
    final newPosition =
        position + Duration(seconds: UserManager().animeSkipSeconds);
    if (newPosition < duration) {
      _player.seek(newPosition);
    } else {
      _player.seek(duration);
    }
  }

  Widget _buildVideoWithControls() {
    return _buildVideoSurface(_videoController, fullscreen: false);
  }

  Future<void> _resumeFromPlaybackRecord() async {
    final record = _playbackRecord;
    if (!_isRestorablePlaybackRecord(record)) return;
    final restored = await _seekToPlaybackProgress(
      record!.position,
      _openMediaSerial,
    );
    if (!mounted) return;
    if (restored) {
      _lastDanmakuSec = -1;
      _showPlayerHint(
        AppLocalizations.of(
          context,
        )!.animePlayerSeekedTo(_formatDuration(record.position)),
      );
    } else {
      _showPlayerHint(
        AppLocalizations.of(context)!.animePlayerSeekLastFailed,
        isError: true,
      );
    }
  }

  Future<String> _normalizedAnimeName() async {
    String animeName = widget.animeName;
    try {
      animeName = await ChineseConverter.convertToSimplifiedChinese(
        widget.animeName,
      );
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'anime_player.convert_anime_name',
        ),
      );
    }
    return animeName;
  }

  Future<void> _loadSavedDanmakuOrSetupSearch(int serial) async {
    final record = _playbackRecord ?? await _loadPlaybackRecord(serial);
    if (!mounted || serial != _danmakuLoadSerial) return;

    final boundEpisodeId = record?.danmakuEpisodeId;
    if (boundEpisodeId != null) {
      setState(() {
        _danmakuSearchCollapsedByBinding = true;
        _danmakuSearchCollapseRevision++;
      });
      await _loadDanmakuForEpisode(
        boundEpisodeId,
        silent: true,
        saveBinding: false,
        serial: serial,
      );
      return;
    }

    final animeName = await _normalizedAnimeName();
    if (!mounted || serial != _danmakuLoadSerial) return;
    final chapterName = _removeParentheses(_currentChapterName);
    _setupSearchSegments(animeName, chapterName);
  }

  void _setupSearchSegments(String animeName, String chapterName) {
    _searchSegments = animeName
        .split(RegExp(r'[\s\p{P}]+', unicode: true))
        .where((s) => s.isNotEmpty)
        .toList();
    if (chapterName.isNotEmpty) _searchSegments.add(chapterName);
    _selectedSegmentIndices = Set.from(
      List.generate(_searchSegments.length, (i) => i),
    );
    _syncSearchText();
    // Show cached results immediately.
    unawaited(_doInlineSearch(showLoading: false));
  }

  void _syncSearchText() {
    final parts = _selectedSegmentIndices
        .map((i) => _searchSegments[i])
        .toList();
    _searchController.text = parts.join(' ');
  }

  void _toggleSearchSegment(int index) {
    setState(() {
      if (_selectedSegmentIndices.contains(index)) {
        if (_selectedSegmentIndices.length > 1) {
          _selectedSegmentIndices.remove(index);
        }
      } else {
        _selectedSegmentIndices.add(index);
      }
    });
    _syncSearchText();
  }

  Future<void> _doInlineSearch({bool showLoading = true}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (showLoading) setState(() => _inlineSearching = true);
    try {
      final results = await DandanplayApi().search(query);
      if (mounted) {
        setState(() {
          _inlineResults = results;
          _inlineSearching = false;
          _hasSearched = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _inlineSearching = false;
          _hasSearched = true;
        });
        if (showLoading) {
          _showPlayerHint(
            AppLocalizations.of(context)!.animePlayerSearchFailed(e.toString()),
            isError: true,
          );
        }
      }
    }
  }

  void _forceRefreshSearch() {
    if (!DandanplayApi().clearSearchCache()) {
      _showPlayerHint(
        AppLocalizations.of(context)!.animePlayerRefreshTooFrequent,
        isError: true,
      );
      return;
    }
    _doInlineSearch();
  }

  Future<bool> _loadDanmakuForEpisode(
    int episodeId, {
    bool silent = false,
    bool saveBinding = true,
    int? serial,
  }) async {
    final targetChapterUuid = _currentChapterUuid;
    final targetChapterName = _currentChapterName;
    bool isCurrentRequest() =>
        mounted &&
        (serial != null
            ? serial == _danmakuLoadSerial
            : targetChapterUuid == _currentChapterUuid);

    if (!isCurrentRequest()) return false;
    if (!silent && mounted) {
      setState(() => _loadingDanmakuEpisodeId = episodeId);
    }
    try {
      final comments = await DandanplayApi().getComments(episodeId);
      if (!isCurrentRequest()) return false;
      final blocklist = _user.danmakuBlocklist;
      final items = <DanmakuContentItem>[];
      final filteredComments = <dynamic>[];
      for (final c in comments) {
        if (blocklist.any((w) => c.text.contains(w))) continue;
        DanmakuItemType mode = DanmakuItemType.scroll;
        if (c.mode == 5) mode = DanmakuItemType.top;
        if (c.mode == 4) mode = DanmakuItemType.bottom;
        final colorStr = c.color.toRadixString(16).padLeft(6, '0');
        items.add(
          DanmakuContentItem(
            c.text,
            type: mode,
            color: Color(int.parse('FF$colorStr', radix: 16)),
          ),
        );
        filteredComments.add(c);
      }
      if (!isCurrentRequest()) return false;
      setState(() {
        _loadingDanmakuEpisodeId = null;
        _selectedDanmakuEpisodeId = episodeId;
        _danmakuItems = {};
        for (int i = 0; i < items.length; i++) {
          final time = filteredComments[i].time.toInt();
          _danmakuItems.putIfAbsent(time, () => []).add(items[i]);
        }
      });
      _lastDanmakuSec = -1;
      if (saveBinding) {
        await AnimePlaybackHistory.saveDanmakuEpisode(
          pathWord: widget.pathWord,
          chapterUuid: targetChapterUuid,
          chapterName: targetChapterName,
          episodeId: episodeId,
        );
        if (mounted && targetChapterUuid == _currentChapterUuid) {
          setState(() {
            _playbackRecord = AnimePlaybackRecord(
              chapterUuid: targetChapterUuid,
              chapterName: targetChapterName,
              position: _playbackRecord?.position ?? Duration.zero,
              duration: _playbackRecord?.duration ?? Duration.zero,
              danmakuEpisodeId: episodeId,
              updatedAt: DateTime.now(),
            );
          });
        }
      }
      // if (!silent) _showPlayerHint('Loaded ${items.length} danmaku items');
      return true;
    } catch (e) {
      debugPrint('LoadDanmaku error: $e');
      final currentRequest = serial != null
          ? serial == _danmakuLoadSerial
          : targetChapterUuid == _currentChapterUuid;
      if (!mounted || !currentRequest) return false;
      if (_loadingDanmakuEpisodeId == episodeId) {
        setState(() => _loadingDanmakuEpisodeId = null);
      }
      if (!silent) {
        _showPlayerHint(
          AppLocalizations.of(
            context,
          )!.animePlayerLoadDanmakuFailed(e.toString()),
          isError: true,
        );
      }
      return false;
    }
  }

  void _toggleDanmaku() {
    if (_danmakuVisible) {
      _danmakuController?.clear();
    }
    setState(() {
      _danmakuVisible = !_danmakuVisible;
    });
    _user.setDanmakuEnabled(_danmakuVisible);
    if (_danmakuVisible) {
      _lastDanmakuSec = -1;
    }
  }

  Widget _buildVideoSurface(
    VideoController controller, {
    required bool fullscreen,
  }) {
    Widget? danmakuView;
    if (_danmakuVisible) {
      danmakuView = DanmakuScreen(
        key: ValueKey('danmaku-$fullscreen-$_danmakuSurfaceGeneration'),
        createdController: (c) {
          _danmakuController = c;
          if (_player.state.playing && _danmakuVisible) {
            c.resume();
          } else {
            c.pause();
          }
        },
        option: DanmakuOption(
          fontSize: _user.danmakuFontSize,
          duration: 8,
          opacity: _user.danmakuOpacity,
          area: _user.danmakuArea,
          hideScroll: _user.danmakuHideScroll,
          hideTop: _user.danmakuHideTop,
          hideBottom: _user.danmakuHideBottom,
        ),
      );
    }

    return _VideoPlayerSurface(
      controller: controller,
      fullscreen: fullscreen,
      danmakuView: danmakuView,
      danmakuVisible: _danmakuVisible,
      onToggleDanmaku: _toggleDanmaku,
      onSkipForward: _skipForward,
      onSettings: _showSettingsPanel,
      chapters: _chapters,
      currentChapterUuid: _currentChapterUuid,
      onChapterSelected: _openChapter,
      title: _title,
      onFullscreen: fullscreen
          ? () => Navigator.maybePop(context)
          : _fullscreen,
    );
  }

  Future<void> _fullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    if (!mounted) return;
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Center(
                child: _buildVideoSurface(_videoController, fullscreen: true),
              ),
            ),
          ),
        ),
      );
    } finally {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      if (mounted && _danmakuVisible) {
        _danmakuController = null;
        _lastDanmakuSec = -1;
        setState(() => _danmakuSurfaceGeneration++);
      }
    }
  }

  void _showSettingsPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      builder: (_) => _PlayerSettingsPanel(
        onChanged: () => setState(() {}),
        danmakuController: _danmakuController,
        danmakuVisible: _danmakuVisible,
        onDanmakuVisibleChanged: (v) {
          setState(() => _danmakuVisible = v);
          _user.setDanmakuEnabled(v);
          if (v) _lastDanmakuSec = -1;
        },
      ),
    );
  }

  List<AnimeChapter> get _chapters {
    if (widget.chapters.isNotEmpty) return widget.chapters;
    return [
      AnimeChapter(
        name: _currentChapterName,
        uuid: _currentChapterUuid,
        vCover: '',
      ),
    ];
  }

  bool get _showLoadingOverlay => _loading || (_buffering && _error == null);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      onPopInvokedWithResult: (_, _) {
        unawaited(_savePlaybackProgress(force: true, updateState: false));
        _player.pause();
      },
      child: Scaffold(
        body: Column(
          children: [
            ColoredBox(
              color: cs.surface,
              child: SafeArea(
                bottom: false,
                child: _VideoTopBar(title: _title),
              ),
            ),
            ColoredBox(
              color: Colors.black,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: _error == null
                          ? _buildVideoWithControls()
                          : _ErrorPanel(
                              message: _error!,
                              rawError: _rawError,
                              requiresLogin: _requiresLogin,
                              onLogin: _goLogin,
                              onRetry: () => _load(),
                              onLogCopied: () => _showPlayerHint(
                                l10n.chapterCommentsLogCopied,
                              ),
                            ),
                    ),
                    if (_showLoadingOverlay)
                      ColoredBox(
                        color: const Color(0x66000000),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const ExpressiveLoadingIndicator(),
                              if (_buffering && !_loading) ...[
                                const SizedBox(height: 12),
                                Text(
                                  l10n.animePlayerBuffering,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  l10n.animePlayerProxySuggestion,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshPlayback,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (_danmakuVisible) ...[
                      if (_isRestorablePlaybackRecord(_playbackRecord)) ...[
                        _PlaybackProgressHint(
                          record: _playbackRecord!,
                          restored: _playbackProgressRestored,
                          onResume: () =>
                              unawaited(_resumeFromPlaybackRecord()),
                        ),
                        const SizedBox(height: 12),
                      ],
                      _InlineSearchPanel(
                        segments: _searchSegments,
                        selectedIndices: _selectedSegmentIndices,
                        searchController: _searchController,
                        results: _inlineResults,
                        searching: _inlineSearching,
                        hasSearched: _hasSearched,
                        selectedEpisodeId: _selectedDanmakuEpisodeId,
                        loadingEpisodeId: _loadingDanmakuEpisodeId,
                        loadedDanmakuCount: _danmakuItems.values.fold<int>(
                          0,
                          (sum, items) => sum + items.length,
                        ),
                        collapsedByBinding: _danmakuSearchCollapsedByBinding,
                        collapseRevision: _danmakuSearchCollapseRevision,
                        onToggleSegment: _toggleSearchSegment,

                        onSearch: _doInlineSearch,
                        onRefresh: _forceRefreshSearch,
                        onSelectResult: (ep) =>
                            unawaited(_loadDanmakuForEpisode(ep.episodeId)),
                      ),
                      const SizedBox(height: 24),
                    ],
                    _ChapterSelector(
                      chapters: _chapters,
                      currentChapterUuid: _currentChapterUuid,
                      onSelected: _openChapter,
                    ),
                    const SizedBox(height: 24),
                    _VideoLinkPanel(
                      videoUrl: _videoUrl,
                      lines: _playback?.chapter.lines ?? const {},
                      currentLine: _line,
                      onCopy: _copyVideoUrl,
                      onOpen: _openVideoUrl,
                      onLineSelected: _switchLine,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
