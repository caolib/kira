import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_dio.dart';
import '../utils/data_cache.dart';

class _CacheEntry {
  final dynamic data;
  final DateTime expiresAt;
  _CacheEntry(this.data, this.expiresAt);
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class DandanplayEpisode {
  final int episodeId;
  final String animeTitle;
  final String episodeTitle;

  DandanplayEpisode({
    required this.episodeId,
    required this.animeTitle,
    required this.episodeTitle,
  });
}

class DandanplayComment {
  final double time;
  final int mode;
  final int color;
  final String text;

  DandanplayComment({
    required this.time,
    required this.mode,
    required this.color,
    required this.text,
  });
}

class DandanplayAnimeSearchItem {
  final int animeId;
  final String bangumiId;
  final String animeTitle;
  final String? typeDescription;
  final String? imageUrl;
  final int episodeCount;
  final double rating;
  final String? startDate;

  DandanplayAnimeSearchItem({
    required this.animeId,
    required this.bangumiId,
    required this.animeTitle,
    this.typeDescription,
    this.imageUrl,
    this.episodeCount = 0,
    this.rating = 0,
    this.startDate,
  });

  factory DandanplayAnimeSearchItem.fromJson(Map<String, dynamic> json) =>
      DandanplayAnimeSearchItem(
        animeId: json['animeId'] as int? ?? 0,
        bangumiId: json['bangumiId']?.toString() ?? '',
        animeTitle: json['animeTitle']?.toString() ?? '',
        typeDescription: json['typeDescription']?.toString(),
        imageUrl: json['imageUrl']?.toString(),
        episodeCount: json['episodeCount'] as int? ?? 0,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
        startDate: json['startDate']?.toString(),
      );
}

class DandanplayBangumiEpisode {
  final int episodeId;
  final String episodeTitle;
  final String episodeNumber;

  DandanplayBangumiEpisode({
    required this.episodeId,
    required this.episodeTitle,
    required this.episodeNumber,
  });

  factory DandanplayBangumiEpisode.fromJson(Map<String, dynamic> json) =>
      DandanplayBangumiEpisode(
        episodeId: json['episodeId'] as int? ?? 0,
        episodeTitle: json['episodeTitle']?.toString() ?? '',
        episodeNumber: json['episodeNumber']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
    'episodeId': episodeId,
    'episodeTitle': episodeTitle,
    'episodeNumber': episodeNumber,
  };
}

class DandanplayBangumi {
  final int animeId;
  final String bangumiId;
  final String animeTitle;
  final String? imageUrl;
  final String? type;
  final String? typeDescription;
  final List<String> titleAliases;
  final List<DandanplayBangumiEpisode> episodes;
  final String? summary;
  final String? intro;
  final List<String> metadata;
  final String? bangumiUrl;
  final Map<String, double> ratingDetails;
  final double rating;
  final bool isOnAir;
  final int? airDay;
  final bool isFavorited;
  final bool isRestricted;

  DandanplayBangumi({
    required this.animeId,
    required this.bangumiId,
    required this.animeTitle,
    this.imageUrl,
    this.type,
    this.typeDescription,
    this.titleAliases = const [],
    this.episodes = const [],
    this.summary,
    this.intro,
    this.metadata = const [],
    this.bangumiUrl,
    this.ratingDetails = const {},
    this.rating = 0,
    this.isOnAir = false,
    this.airDay,
    this.isFavorited = false,
    this.isRestricted = false,
  });

  factory DandanplayBangumi.fromJson(Map<String, dynamic> json) {
    final titles =
        (json['titles'] as List?)
            ?.map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    final episodes =
        (json['episodes'] as List?)
            ?.map(
              (e) => DandanplayBangumiEpisode.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList() ??
        const <DandanplayBangumiEpisode>[];
    final metadata =
        (json['metadata'] as List?)
            ?.map((item) => item?.toString() ?? '')
            .where((item) => item.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final ratingDetails = <String, double>{};
    if (json['ratingDetails'] is Map) {
      for (final entry in Map<String, dynamic>.from(
        json['ratingDetails'],
      ).entries) {
        ratingDetails[entry.key] = (entry.value as num?)?.toDouble() ?? 0;
      }
    }
    return DandanplayBangumi(
      animeId: json['animeId'] as int? ?? 0,
      bangumiId: json['bangumiId']?.toString() ?? '',
      animeTitle: json['animeTitle']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString(),
      type: json['type']?.toString(),
      typeDescription: json['typeDescription']?.toString(),
      titleAliases: titles
          .map((item) => item['title']?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      episodes: episodes,
      summary: json['summary']?.toString(),
      intro: json['intro']?.toString(),
      metadata: metadata,
      bangumiUrl: json['bangumiUrl']?.toString(),
      ratingDetails: ratingDetails,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      isOnAir: json['isOnAir'] == true,
      airDay: json['airDay'] as int?,
      isFavorited: json['isFavorited'] == true,
      isRestricted: json['isRestricted'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'animeId': animeId,
    'bangumiId': bangumiId,
    'animeTitle': animeTitle,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (type != null) 'type': type,
    if (typeDescription != null) 'typeDescription': typeDescription,
    'titles': titleAliases.map((title) => {'title': title}).toList(),
    'episodes': episodes.map((e) => e.toJson()).toList(),
    if (summary != null) 'summary': summary,
    if (intro != null) 'intro': intro,
    'metadata': metadata,
    if (bangumiUrl != null) 'bangumiUrl': bangumiUrl,
    'ratingDetails': ratingDetails,
    'rating': rating,
    'isOnAir': isOnAir,
    if (airDay != null) 'airDay': airDay,
    'isFavorited': isFavorited,
    'isRestricted': isRestricted,
  };
}

class DandanplayBangumiComment {
  final int id;
  final int userId;
  final String externalUserId;
  final String userName;
  final String imageUrl;
  final String source;
  final String text;
  final int rating;
  final String updatedTime;

  DandanplayBangumiComment({
    required this.id,
    required this.userId,
    required this.externalUserId,
    required this.userName,
    required this.imageUrl,
    required this.source,
    required this.text,
    required this.rating,
    required this.updatedTime,
  });

  factory DandanplayBangumiComment.fromJson(Map<String, dynamic> json) =>
      DandanplayBangumiComment(
        id: json['id'] as int? ?? 0,
        userId: json['userId'] as int? ?? 0,
        externalUserId: json['externalUserId']?.toString() ?? '',
        userName: json['userName']?.toString() ?? '',
        imageUrl: json['imageUrl']?.toString() ?? '',
        source: json['source']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
        rating: json['rating'] as int? ?? 0,
        updatedTime: json['updatedTime']?.toString() ?? '',
      );
}

class DandanplayBangumiCommentsPage {
  final int count;
  final bool hasMore;
  final List<DandanplayBangumiComment> comments;

  const DandanplayBangumiCommentsPage({
    required this.count,
    required this.hasMore,
    required this.comments,
  });
}

class DandanplayApi {
  static const _baseUrl = 'https://api.dandanplay.net';

  // 从环境变量中读取
  static const String appId = String.fromEnvironment('DANDANPLAY_APP_ID');
  static const String appSecret = String.fromEnvironment(
    'DANDANPLAY_APP_SECRET',
  );

  static final DandanplayApi _instance = DandanplayApi._();
  factory DandanplayApi() => _instance;

  late final Dio _dio;
  final DataCache _dataCache = DataCache();
  final Map<String, _CacheEntry> _cache = {};
  final Map<int, Future<DandanplayBangumi?>> _bangumiInFlight = {};
  DateTime? _lastClearTime;

  // 缓存时长：根据弹弹play官方建议
  static const _ttlSearch = Duration(hours: 6); // 搜索结果 6小时
  static const _ttlComments = Duration(hours: 1); // 弹幕 1小时（较活跃）

  String _cacheKey(String endpoint, [Map<String, dynamic>? params]) {
    final sorted = params?.entries.toList()
      ?..sort((a, b) => a.key.compareTo(b.key));
    return '$endpoint${sorted != null ? jsonEncode(sorted.map((e) => [e.key, e.value]).toList()) : ''}';
  }

  T? _getCache<T>(String key) {
    final entry = _cache[key];
    if (entry != null && !entry.isExpired) return entry.data as T;
    _cache.remove(key);
    return null;
  }

  void _setCache(String key, dynamic data, Duration ttl) {
    _cache[key] = _CacheEntry(data, DateTime.now().add(ttl));
  }

  DandanplayApi._() {
    _dio = AppDio.create(
      source: 'dandanplay',
      options: BaseOptions(baseUrl: _baseUrl),
      interceptors: [
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (appId.isNotEmpty && appSecret.isNotEmpty) {
              final path = options.path.split('?').first;
              final timestamp =
                  (DateTime.now().toUtc().millisecondsSinceEpoch / 1000)
                      .floor()
                      .toString();

              final data = appId + timestamp + path + appSecret;
              final signature = base64Encode(
                sha256.convert(utf8.encode(data)).bytes,
              );

              options.headers['X-AppId'] = appId;
              options.headers['X-Timestamp'] = timestamp;
              options.headers['X-Signature'] = signature;
            }
            handler.next(options);
          },
        ),
      ],
    );
  }

  Future<List<DandanplayEpisode>> search(String animeName) async {
    final key = _cacheKey('/api/v2/search/episodes', {'anime': animeName});
    final cached = _getCache<List<DandanplayEpisode>>(key);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '/api/v2/search/episodes',
        queryParameters: {'anime': animeName},
      );
      if (response.data['success'] == true) {
        final animes = response.data['animes'] as List;
        final results = <DandanplayEpisode>[];
        for (final anime in animes) {
          final animeTitle = anime['animeTitle'] as String;
          final episodes = anime['episodes'] as List;
          for (final ep in episodes) {
            results.add(
              DandanplayEpisode(
                episodeId: ep['episodeId'] as int,
                animeTitle: animeTitle,
                episodeTitle: ep['episodeTitle'] as String,
              ),
            );
          }
        }
        _setCache(key, results, _ttlSearch);
        return results;
      }
    } catch (e) {
      debugPrint('Dandanplay search error: $e');
    }
    return [];
  }

  /// 按关键词搜索动漫列表（不含 episodes，仅返回动漫基本信息）
  Future<List<DandanplayAnimeSearchItem>> searchAnime(String keyword) async {
    final key = _cacheKey('/api/v2/search/anime', {'keyword': keyword});
    final cached = _getCache<List<DandanplayAnimeSearchItem>>(key);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '/api/v2/search/anime',
        queryParameters: {'keyword': keyword},
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        final animes = (data['animes'] as List?) ?? const [];
        final results = animes
            .map(
              (e) => DandanplayAnimeSearchItem.fromJson(
                Map<String, dynamic>.from(e),
              ),
            )
            .toList();
        _setCache(key, results, _ttlSearch);
        return results;
      }
    } catch (e) {
      debugPrint('Dandanplay searchAnime error: $e');
    }
    return [];
  }

  /// 获取番剧详情（含所有 episodes）
  Future<DandanplayBangumi?> getBangumi(int animeId) async {
    final key = _cacheKey('/api/v2/bangumi/$animeId');
    final cached = _getCache<DandanplayBangumi>(key);
    if (cached != null) return cached;

    final persistentKey = _bangumiCacheKey(animeId);
    final persistentCached = await _dataCache.get(persistentKey);
    if (persistentCached is Map) {
      try {
        final bangumi = DandanplayBangumi.fromJson(
          Map<String, dynamic>.from(persistentCached),
        );
        _setCache(key, bangumi, _ttlSearch);
        return bangumi;
      } catch (_) {
        await _dataCache.remove(persistentKey);
      }
    }

    final inFlight = _bangumiInFlight[animeId];
    if (inFlight != null) return inFlight;

    final request = _fetchBangumi(animeId, key);
    _bangumiInFlight[animeId] = request;
    try {
      return await request;
    } finally {
      unawaited(_bangumiInFlight.remove(animeId));
    }
  }

  String _bangumiCacheKey(int animeId) => 'dandanplay_bangumi_v1_$animeId';

  Future<DandanplayBangumi?> _fetchBangumi(int animeId, String key) async {
    try {
      final response = await _dio.get('/api/v2/bangumi/$animeId');
      final data = response.data;
      if (data is Map && data['success'] == true && data['bangumi'] is Map) {
        final bangumi = DandanplayBangumi.fromJson(
          Map<String, dynamic>.from(data['bangumi']),
        );
        _setCache(key, bangumi, _ttlSearch);
        await _dataCache.put(
          _bangumiCacheKey(animeId),
          bangumi.toJson(),
          ttl: _ttlSearch,
        );
        return bangumi;
      }
    } catch (e) {
      debugPrint('Dandanplay getBangumi error: $e');
    }
    return null;
  }

  Future<void> clearBangumiCache(int animeId) async {
    _cache.remove(_cacheKey('/api/v2/bangumi/$animeId'));
    unawaited(_bangumiInFlight.remove(animeId));
    await _dataCache.remove(_bangumiCacheKey(animeId));
  }

  bool _clearCacheWhere(bool Function(String key) shouldRemove) {
    final now = DateTime.now();
    if (_lastClearTime != null &&
        now.difference(_lastClearTime!).inSeconds < 60) {
      return false;
    }
    _lastClearTime = now;
    _cache.removeWhere((key, _) => shouldRemove(key));
    return true;
  }

  /// 清除搜索缓存，限制1分钟内只能清除一次。
  /// 不清除弹幕评论缓存，避免影响已选弹幕来源的加载。
  bool clearSearchCache() {
    return _clearCacheWhere(
      (key) =>
          key.startsWith('/api/v2/search/episodes') ||
          key.startsWith('/api/v2/search/anime') ||
          key.startsWith('/api/v2/bangumi/'),
    );
  }

  /// 清除全部弹弹play缓存，限制1分钟内只能清除一次
  bool clearCache() {
    return _clearCacheWhere((_) => true);
  }

  Future<List<DandanplayComment>> getComments(int episodeId) async {
    final key = _cacheKey('/api/v2/comment/$episodeId');
    final cached = _getCache<List<DandanplayComment>>(key);
    if (cached != null) return cached;

    try {
      final response = await _dio.get(
        '/api/v2/comment/$episodeId',
        queryParameters: {'withRelated': 'true'},
      );
      final data = response.data;
      if (data is Map && data['comments'] is List) {
        final comments = data['comments'] as List;
        final results = <DandanplayComment>[];
        for (final c in comments) {
          try {
            final p = c['p'].toString().split(',');
            if (p.length < 3) continue;
            results.add(
              DandanplayComment(
                time: double.parse(p[0]),
                mode: int.parse(p[1]),
                color: int.parse(p[2]),
                text: c['m'] as String,
              ),
            );
          } catch (e) {
            continue;
          }
        }
        _setCache(key, results, _ttlComments);
        return results;
      }
    } catch (e) {
      debugPrint('Dandanplay get comments error: $e');
    }
    return [];
  }

  Future<DandanplayBangumiCommentsPage> getBangumiComments(
    String bangumiId, {
    int page = 0,
    bool forceRefresh = false,
  }) async {
    final normalizedBangumiId = bangumiId.trim();
    if (normalizedBangumiId.isEmpty) {
      throw ArgumentError.value(bangumiId, 'bangumiId', '不能为空');
    }
    if (page < 0 || page > 9) {
      throw RangeError.range(page, 0, 9, 'page');
    }

    final endpoint =
        '/api/v2/bangumi/${Uri.encodeComponent(normalizedBangumiId)}/comments';
    final key = _cacheKey(endpoint, {'page': page});
    if (!forceRefresh) {
      final cached = _getCache<DandanplayBangumiCommentsPage>(key);
      if (cached != null) return cached;
    } else {
      _cache.remove(key);
    }

    try {
      final response = await _dio.get(
        endpoint,
        queryParameters: {'page': page},
      );
      final data = response.data;
      if (data is Map && data['success'] == true) {
        final comments = (data['comments'] as List? ?? const [])
            .map(
              (item) => DandanplayBangumiComment.fromJson(
                Map<String, dynamic>.from(item),
              ),
            )
            .toList(growable: false);
        final result = DandanplayBangumiCommentsPage(
          count: data['count'] as int? ?? comments.length,
          hasMore: data['hasMore'] == true,
          comments: comments,
        );
        _setCache(key, result, _ttlComments);
        return result;
      }
      throw StateError(
        data is Map ? data['errorMessage']?.toString() ?? '未知错误' : '响应格式错误',
      );
    } catch (e) {
      debugPrint('Dandanplay get bangumi comments error: $e');
      throw Exception('获取番剧评论失败');
    }
  }
}
