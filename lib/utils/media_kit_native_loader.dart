import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import '../models/user_manager.dart';
import 'app_logger.dart';

/// Download source for media_kit native libraries.
enum MediaKitDownloadSource { github, mirror }

/// Cancel handle for [MediaKitNativeLoader.downloadAndInstall].
class MediaKitDownloadCancelToken {
  bool _cancelled = false;
  HttpClientRequest? _request;
  HttpClient? _client;

  bool get isCancelled => _cancelled;

  void cancel([String? reason]) {
    if (_cancelled) return;
    _cancelled = true;
    try {
      _request?.abort();
    } catch (_) {}
    try {
      _client?.close(force: true);
    } catch (_) {}
  }

  void _attach(HttpClient client, HttpClientRequest request) {
    _client = client;
    _request = request;
    if (_cancelled) {
      cancel();
    }
  }
}

/// Progress of native library download / install.
class MediaKitNativeProgress {
  /// 0.0–1.0 when known; null for indeterminate.
  final double? fraction;
  final String stage;
  final int receivedBytes;
  final int? totalBytes;

  /// Short human-readable status (e.g. host / phase detail).
  final String? detail;

  const MediaKitNativeProgress({
    this.fraction,
    required this.stage,
    this.receivedBytes = 0,
    this.totalBytes,
    this.detail,
  });
}

class _NativeArtifact {
  final String file;
  final String md5;
  final int sizeBytes;

  const _NativeArtifact({
    required this.file,
    required this.md5,
    required this.sizeBytes,
  });
}

/// Downloads and loads media_kit native libs (libmpv) on Android on demand.
///
/// Windows keeps bundling `media_kit_libs_windows_video` in the installer.
class MediaKitNativeLoader {
  MediaKitNativeLoader._();
  static final MediaKitNativeLoader instance = MediaKitNativeLoader._();

  static const _channel = MethodChannel('io.github.caolib.kira/native_libs');
  static const nativeLibVersion = 'v1.1.7';
  static const _dirName = 'media_kit_native';
  static const _versionFileName = 'version.txt';
  static const _mpvFileName = 'libmpv.so';
  static const _helperFileName = 'libmediakitandroidhelper.so';

  /// Official jars used by media_kit_libs_android_video 1.3.8.
  static const _artifacts = <String, _NativeArtifact>{
    'arm64-v8a': _NativeArtifact(
      file: 'default-arm64-v8a.jar',
      md5: '83df25b61193af8fa815e373143ac9af',
      sizeBytes: 5729978,
    ),
    'armeabi-v7a': _NativeArtifact(
      file: 'default-armeabi-v7a.jar',
      md5: '22e21526fefc0a2b8f17adbec9f57590',
      sizeBytes: 5499353,
    ),
    'x86_64': _NativeArtifact(
      file: 'default-x86_64.jar',
      md5: '6fa26bf0459b11f1c0b0dbc29e5b940d',
      sizeBytes: 6516632,
    ),
    'x86': _NativeArtifact(
      file: 'default-x86.jar',
      md5: '0d742b756dc9d1fcd84ea271d8b68f32',
      sizeBytes: 5839220,
    ),
  };

  static const _githubReleaseBase =
      'https://github.com/media-kit/libmpv-android-video-build/releases/download/$nativeLibVersion';

  bool _initialized = false;
  Future<void>? _initFuture;

  /// Approximate download size for UI copy (arm64 jar is ~5.5MB).
  static const approximateSizeLabel = '约 6 MB';

  bool get needsOnDemandDownload => !kIsWeb && Platform.isAndroid;

  /// Whether [ensureInitialized] has completed successfully in this process.
  bool get isInitialized => _initialized;

  Future<bool> get isInstalled async {
    if (!needsOnDemandDownload) return true;
    final dir = await _nativeDir();
    final versionFile = File('${dir.path}/$_versionFileName');
    final mpv = File('${dir.path}/$_mpvFileName');
    final helper = File('${dir.path}/$_helperFileName');
    if (!versionFile.existsSync() ||
        !mpv.existsSync() ||
        !helper.existsSync()) {
      return false;
    }
    final version = (await versionFile.readAsString()).trim();
    return version == nativeLibVersion;
  }

  /// Disk usage of the on-demand native library directory (Android only).
  Future<MediaKitNativeInstallInfo> installInfo() async {
    if (!needsOnDemandDownload) {
      return const MediaKitNativeInstallInfo.empty();
    }
    final dir = await _nativeDir();
    if (!await dir.exists()) {
      return MediaKitNativeInstallInfo(
        directoryPath: dir.path,
        fileCount: 0,
        sizeBytes: 0,
        version: null,
        isInstalled: false,
      );
    }

    var fileCount = 0;
    var sizeBytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      fileCount += 1;
      try {
        sizeBytes += await entity.length();
      } catch (_) {}
    }

    String? version;
    final versionFile = File('${dir.path}/$_versionFileName');
    if (await versionFile.exists()) {
      try {
        version = (await versionFile.readAsString()).trim();
      } catch (_) {}
    }

    final installed =
        version == nativeLibVersion &&
        await File('${dir.path}/$_mpvFileName').exists() &&
        await File('${dir.path}/$_helperFileName').exists();

    return MediaKitNativeInstallInfo(
      directoryPath: dir.path,
      fileCount: fileCount,
      sizeBytes: sizeBytes,
      version: version,
      isInstalled: installed,
    );
  }

  /// Deletes downloaded native libraries from disk.
  ///
  /// Does not unload already-loaded `.so` from the current process; the next
  /// cold start (or next play after re-download) will fetch them again.
  Future<void> uninstall() async {
    if (!needsOnDemandDownload) return;

    final dir = await _nativeDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }

    _initialized = false;
    _initFuture = null;

    unawaited(
      AppLogger.instance.recordInfo(
        'media_kit native libraries uninstalled',
        source: 'media_kit_native',
      ),
    );
  }

  /// GitHub direct URL for the current device ABI.
  Future<String> githubDownloadUrl() async {
    final artifact = await _resolveArtifact();
    return '$_githubReleaseBase/${artifact.file}';
  }

  /// Mirror URL using [UserManager.updateMirrorPrefix], same as app update.
  Future<String> mirrorDownloadUrl() async {
    final github = await githubDownloadUrl();
    return '${UserManager().updateMirrorPrefix}$github';
  }

  /// Ensures media_kit is initialized. On Android, requires native libs installed.
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initFuture ??= _doEnsureInitialized();
    try {
      await _initFuture;
    } catch (e) {
      _initFuture = null;
      rethrow;
    }
  }

  Future<void> _doEnsureInitialized() async {
    if (!needsOnDemandDownload) {
      MediaKit.ensureInitialized();
      _initialized = true;
      return;
    }

    if (!await isInstalled) {
      throw StateError('media_kit native libraries are not installed');
    }

    final dir = await _nativeDir();
    final mpvPath = '${dir.path}/$_mpvFileName';
    final helperPath = '${dir.path}/$_helperFileName';

    // MainActivity System.load + MediaKitAndroidHelper.setApplicationContextJava.
    // The latter stores JavaVM; media_kit AndroidHelper busy-waits on it.
    await _channel.invokeMethod<void>('loadLibraries', {
      'paths': [helperPath, mpvPath],
    });

    MediaKit.ensureInitialized(libmpv: mpvPath);
    _initialized = true;
  }

  /// Download, verify, extract and load native libraries.
  Future<void> downloadAndInstall({
    required MediaKitDownloadSource source,
    void Function(MediaKitNativeProgress progress)? onProgress,
    MediaKitDownloadCancelToken? cancelToken,
  }) async {
    if (!needsOnDemandDownload) {
      await ensureInitialized();
      return;
    }

    void emit(MediaKitNativeProgress p) => onProgress?.call(p);

    emit(const MediaKitNativeProgress(stage: 'prepare', detail: '准备环境'));

    final artifact = await _resolveArtifact();
    final githubUrl = '$_githubReleaseBase/${artifact.file}';
    final url = source == MediaKitDownloadSource.mirror
        ? '${UserManager().updateMirrorPrefix}$githubUrl'
        : githubUrl;
    final host = Uri.tryParse(url)?.host ?? url;

    debugPrint(
      '[media_kit_native] download url=$url artifact=${artifact.file}',
    );
    unawaited(
      AppLogger.instance.recordInfo(
        'media_kit native download start: $url',
        source: 'media_kit_native',
      ),
    );

    if (cancelToken?.isCancelled ?? false) {
      throw const MediaKitDownloadCancelled();
    }

    final dir = await _nativeDir();
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final jarFile = File('${dir.path}/${artifact.file}');
    final partialFile = File('${jarFile.path}.part');
    if (partialFile.existsSync()) {
      await partialFile.delete();
    }
    if (jarFile.existsSync()) {
      await jarFile.delete();
    }

    emit(
      MediaKitNativeProgress(
        stage: 'connect',
        totalBytes: artifact.sizeBytes,
        detail: '连接 $host',
      ),
    );

    try {
      await _downloadWithHttpClient(
        url: url,
        savePath: partialFile.path,
        expectedSize: artifact.sizeBytes,
        cancelToken: cancelToken,
        onProgress: emit,
        hostLabel: host,
      );
    } catch (e, stack) {
      if (e is! MediaKitDownloadCancelled) {
        unawaited(
          AppLogger.instance.recordWarning(
            e,
            stackTrace: stack,
            source: 'media_kit_native.download',
          ),
        );
      }
      try {
        if (partialFile.existsSync()) await partialFile.delete();
      } catch (_) {}
      rethrow;
    }

    if (!partialFile.existsSync()) {
      throw StateError('Download finished but file is missing');
    }
    final downloadedSize = await partialFile.length();
    if (downloadedSize <= 1024) {
      throw StateError(
        'Downloaded file too small ($downloadedSize bytes). '
        'URL may be blocked or returned an error page.',
      );
    }
    await partialFile.rename(jarFile.path);

    // UI: keep elapsed timer running while background isolate works.
    emit(
      MediaKitNativeProgress(
        fraction: 0.92,
        stage: 'extract',
        receivedBytes: downloadedSize,
        totalBytes: downloadedSize,
        detail: '校验并解压（后台进行，约几秒）',
      ),
    );

    debugPrint('[media_kit_native] extract start jar=${jarFile.path}');
    try {
      // Must not close over onProgress/State (Timer is unsendable across isolates).
      await _extractNativeLibsInBackground(
        jarPath: jarFile.path,
        destDirPath: dir.path,
        expectedMd5: artifact.md5,
        mpvFileName: _mpvFileName,
        helperFileName: _helperFileName,
      );
    } catch (e) {
      try {
        if (jarFile.existsSync()) await jarFile.delete();
      } catch (_) {}
      rethrow;
    }
    debugPrint('[media_kit_native] extract done');

    try {
      if (jarFile.existsSync()) {
        await jarFile.delete();
      }
    } catch (e, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'media_kit_native.cleanup_jar',
        ),
      );
    }

    await File('${dir.path}/$_versionFileName').writeAsString(nativeLibVersion);

    emit(
      const MediaKitNativeProgress(
        fraction: 0.98,
        stage: 'load',
        detail: '加载原生库',
      ),
    );
    // Let Flutter paint the "load" stage before System.load.
    await Future<void>.delayed(Duration.zero);

    _initialized = false;
    _initFuture = null;
    await ensureInitialized();

    emit(
      const MediaKitNativeProgress(fraction: 1, stage: 'done', detail: '完成'),
    );
  }

  Future<void> _downloadWithHttpClient({
    required String url,
    required String savePath,
    required int expectedSize,
    required String hostLabel,
    MediaKitDownloadCancelToken? cancelToken,
    required void Function(MediaKitNativeProgress progress) onProgress,
  }) async {
    final client = HttpClient();
    // App proxy is for video sites; GitHub/mirror should go direct.
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 15);
    client.idleTimeout = const Duration(seconds: 20);
    client.userAgent = 'Kira-App';
    client.autoUncompress = false;

    IOSink? sink;
    try {
      final uri = Uri.parse(url);
      final request = await client
          .getUrl(uri)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('连接超时: $hostLabel');
            },
          );
      cancelToken?._attach(client, request);

      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Kira-App',
      );

      if (cancelToken?.isCancelled ?? false) {
        throw const MediaKitDownloadCancelled();
      }

      onProgress(
        MediaKitNativeProgress(
          stage: 'connect',
          totalBytes: expectedSize,
          detail: '等待响应 $hostLabel',
        ),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          throw TimeoutException('等待响应超时: $hostLabel');
        },
      );

      final status = response.statusCode;
      debugPrint(
        '[media_kit_native] response status=$status '
        'contentLength=${response.contentLength} host=$hostLabel',
      );

      if (status < 200 || status >= 300) {
        throw HttpException('HTTP $status from $hostLabel', uri: uri);
      }

      final total = response.contentLength > 0
          ? response.contentLength
          : expectedSize;

      onProgress(
        MediaKitNativeProgress(
          fraction: 0,
          stage: 'download',
          totalBytes: total,
          detail: '开始接收 $hostLabel',
        ),
      );

      sink = File(savePath).openWrite();
      var received = 0;
      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

      await for (final chunk in response) {
        if (cancelToken?.isCancelled ?? false) {
          throw const MediaKitDownloadCancelled();
        }
        sink.add(chunk);
        received += chunk.length;

        final now = DateTime.now();
        final isDone = total > 0 && received >= total;
        if (isDone ||
            now.difference(lastEmit) >= const Duration(milliseconds: 150)) {
          lastEmit = now;
          final fraction = total > 0
              ? (received / total).clamp(0.0, 0.99)
              : null;
          onProgress(
            MediaKitNativeProgress(
              fraction: fraction,
              stage: 'download',
              receivedBytes: received,
              totalBytes: total > 0 ? total : expectedSize,
              detail: hostLabel,
            ),
          );
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (received <= 0) {
        throw StateError('未收到任何数据: $hostLabel');
      }

      onProgress(
        MediaKitNativeProgress(
          fraction: 0.9,
          stage: 'download',
          receivedBytes: received,
          totalBytes: received,
          detail: '下载完成 $hostLabel',
        ),
      );
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  Future<_NativeArtifact> _resolveArtifact() async {
    final abi = await _primaryAbi();
    return _artifacts[abi] ?? _artifacts['arm64-v8a']!;
  }

  Future<String> _primaryAbi() async {
    try {
      final abi = await _channel
          .invokeMethod<String>('getPrimaryAbi')
          .timeout(const Duration(seconds: 2));
      if (abi != null && abi.isNotEmpty) {
        debugPrint('[media_kit_native] primary abi=$abi');
        return abi;
      }
    } catch (e, stack) {
      debugPrint('[media_kit_native] getPrimaryAbi failed: $e');
      unawaited(
        AppLogger.instance.recordWarning(
          e,
          stackTrace: stack,
          source: 'media_kit_native.get_abi',
        ),
      );
    }
    return 'arm64-v8a';
  }

  Future<Directory> _nativeDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/$_dirName');
  }
}

class MediaKitDownloadCancelled implements Exception {
  const MediaKitDownloadCancelled();

  @override
  String toString() => 'Download cancelled';
}

/// Snapshot of on-disk media_kit native library install state.
class MediaKitNativeInstallInfo {
  final String directoryPath;
  final int fileCount;
  final int sizeBytes;
  final String? version;
  final bool isInstalled;

  const MediaKitNativeInstallInfo({
    required this.directoryPath,
    required this.fileCount,
    required this.sizeBytes,
    required this.version,
    required this.isInstalled,
  });

  const MediaKitNativeInstallInfo.empty()
    : directoryPath = '',
      fileCount = 0,
      sizeBytes = 0,
      version = null,
      isInstalled = false;

  bool get isEmpty => fileCount == 0 && sizeBytes == 0;
}

/// Isolate entry that only closes over sendable [String]s (not UI callbacks).
Future<void> _extractNativeLibsInBackground({
  required String jarPath,
  required String destDirPath,
  required String expectedMd5,
  required String mpvFileName,
  required String helperFileName,
}) {
  return Isolate.run(
    () => _verifyAndExtractSoFilesSync(
      jarPath: jarPath,
      destDirPath: destDirPath,
      expectedMd5: expectedMd5,
      mpvFileName: mpvFileName,
      helperFileName: helperFileName,
    ),
  );
}

/// Runs in a background isolate: MD5 check + extract libmpv / helper .so.
void _verifyAndExtractSoFilesSync({
  required String jarPath,
  required String destDirPath,
  required String expectedMd5,
  required String mpvFileName,
  required String helperFileName,
}) {
  final jarFile = File(jarPath);
  final bytes = jarFile.readAsBytesSync();
  final digest = md5.convert(bytes).toString();
  if (digest != expectedMd5) {
    throw StateError('MD5 mismatch: expected $expectedMd5, got $digest');
  }

  final archive = ZipDecoder().decodeBytes(bytes);
  var wroteMpv = false;
  var wroteHelper = false;

  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    final base = name.split('/').last;
    if (base != mpvFileName && base != helperFileName) continue;

    final outPath = '$destDirPath${Platform.pathSeparator}$base';
    final data = entry.readBytes() ?? entry.content;
    if (data.isEmpty) {
      throw StateError('Empty archive entry: $base');
    }
    File(outPath).writeAsBytesSync(data, flush: true);

    if (base == mpvFileName) {
      wroteMpv = true;
    } else if (base == helperFileName) {
      wroteHelper = true;
    }

    if (wroteMpv && wroteHelper) break;
  }

  if (!wroteMpv || !wroteHelper) {
    throw StateError(
      'Native libraries missing in archive '
      '(mpv=$wroteMpv, helper=$wroteHelper)',
    );
  }

  final mpvSize = File(
    '$destDirPath${Platform.pathSeparator}$mpvFileName',
  ).lengthSync();
  if (mpvSize < 1024 * 1024) {
    throw StateError('Extracted libmpv.so too small: $mpvSize bytes');
  }
}
