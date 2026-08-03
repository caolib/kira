part of '../reader_page.dart';

class _ReaderImageFileService extends FileService {
  _ReaderImageFileService(this.timeout)
    : _httpClient = HttpClient()..connectionTimeout = timeout;

  final Duration timeout;
  final HttpClient _httpClient;

  static const _defaultHeaders = {
    'user-agent':
        'Mozilla/5.0 (Linux; Android 12; 23117RK66C Build/V417IR; wv) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
        'Chrome/110.0.5481.154 Mobile Safari/537.36',
    'accept':
        'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    'x-requested-with': 'com.manga2020.app',
    'sec-fetch-site': 'cross-site',
    'sec-fetch-mode': 'no-cors',
    'sec-fetch-dest': 'image',
    'accept-encoding': 'gzip, deflate',
    'accept-language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final stopwatch = Stopwatch()..start();
    final request = await _httpClient.getUrl(Uri.parse(url)).timeout(timeout);
    _defaultHeaders.forEach(request.headers.set);
    headers?.forEach(request.headers.add);

    // 命中缓存不会走到这里；只有真实网络请求才有归属，供阅读统计埋点反查。
    final statsOwner = _statsImageOwnerByUrl[url];
    final response = await request.close().timeout(timeout);
    return _ReaderImageFileServiceResponse(
      response,
      timeout,
      stopwatch,
      statsOwner,
    );
  }
}

class _ReaderImageFileServiceResponse implements FileServiceResponse {
  static const Map<String, String> _imageExtensions = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'image/bmp': '.bmp',
    'image/svg+xml': '.svg',
    'image/tiff': '.tiff',
    'image/vnd.microsoft.icon': '.ico',
  };

  _ReaderImageFileServiceResponse(
    this._response,
    this._timeout,
    this._stopwatch,
    this._statsOwner,
  );

  final HttpClientResponse _response;
  final Duration _timeout;
  final Stopwatch _stopwatch;
  final DateTime _receivedTime = DateTime.now();

  /// 该图片 URL 登记的归属（漫画 + 章节）。未登记（非章节图/异常）为 null。
  final ({String pathWord, String chapterUuid})? _statsOwner;

  bool _recorded = false;

  @override
  Stream<List<int>> get content {
    return _response
        .timeout(_timeout)
        .transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleDone: (sink) {
              if (!_recorded) {
                _recorded = true;
                _stopwatch.stop();
                ImageLoadStats().record(_stopwatch.elapsed);
                // 阅读统计：与 ImageLoadStats 同口径，仅真实网络请求计入。
                final owner = _statsOwner;
                if (owner != null) {
                  final meta = _statsComicMetaByPath[owner.pathWord];
                  unawaited(
                    ReadingStats.recordImageLoad(
                      pathWord: owner.pathWord,
                      chapterUuid: owner.chapterUuid,
                      comicName: meta?.name,
                      tags: meta?.tags,
                    ),
                  );
                }
              }
              sink.close();
            },
            handleError: (error, stackTrace, sink) {
              _recorded = true;
              sink.addError(error, stackTrace);
            },
          ),
        );
  }

  @override
  int? get contentLength =>
      _response.contentLength >= 0 ? _response.contentLength : null;

  @override
  int get statusCode => _response.statusCode;

  @override
  DateTime get validTill {
    var ageDuration = const Duration(days: 7);
    final controlHeader = _response.headers.value(
      HttpHeaders.cacheControlHeader,
    );
    if (controlHeader != null) {
      final controlSettings = controlHeader.split(',');
      for (final setting in controlSettings) {
        final sanitizedSetting = setting.trim().toLowerCase();
        if (sanitizedSetting == 'no-cache') {
          ageDuration = Duration.zero;
        }
        if (sanitizedSetting.startsWith('max-age=')) {
          final validSeconds =
              int.tryParse(sanitizedSetting.split('=')[1]) ?? 0;
          if (validSeconds > 0) {
            ageDuration = Duration(seconds: validSeconds);
          }
        }
      }
    }

    return _receivedTime.add(ageDuration);
  }

  @override
  String? get eTag => _response.headers.value(HttpHeaders.etagHeader);

  @override
  String get fileExtension {
    final contentTypeHeader = _response.headers.value(
      HttpHeaders.contentTypeHeader,
    );
    if (contentTypeHeader == null) return '';

    try {
      final contentType = ContentType.parse(contentTypeHeader);
      return _imageExtensions[contentType.mimeType] ??
          '.${contentType.subType}';
    } catch (_) {
      return '';
    }
  }
}
