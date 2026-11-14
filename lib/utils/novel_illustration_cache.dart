import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_logger.dart';

/// 可清理的在线插图缓存，与永久下载及带漫画请求头的图片缓存独立。
class NovelIllustrationCache {
  NovelIllustrationCache({BaseCacheManager? cacheManager})
    : _injectedManager = cacheManager;

  static const cacheKey = 'novelIllustrationCache';
  static const _ttl = Duration(days: 7);
  static final instance = NovelIllustrationCache();

  // Config/CacheManager 构造会打开目录和索引，仅在首次读图或清理时创建。
  static final _defaultManager = CacheManager(
    Config(cacheKey, stalePeriod: _ttl, maxNrOfCacheObjects: 300),
  );
  static final _states = Expando<_IllustrationCacheState>();

  final BaseCacheManager? _injectedManager;

  BaseCacheManager get _manager => _injectedManager ?? _defaultManager;

  _IllustrationCacheState _stateFor(BaseCacheManager manager) =>
      _states[manager] ??= _IllustrationCacheState();

  /// 只按 URL 查磁盘；未命中由调用方的小说 API 加载，不使用 fileService。
  /// 同一 manager 的所有服务实例共用在途请求，完成或失败即释放字节。
  Future<List<int>> loadBytes(
    String url, {
    required Future<List<int>> Function() load,
  }) {
    final manager = _manager;
    final state = _stateFor(manager);
    final existing = state.inFlight[url];
    if (existing != null) return existing;

    late final Future<List<int>> pending;
    pending = _loadBytes(manager, state, state.generation, url, load)
        .whenComplete(() {
          if (identical(state.inFlight[url], pending)) {
            state.inFlight.remove(url);
          }
        });
    state.inFlight[url] = pending;
    return pending;
  }

  Future<List<int>> _loadBytes(
    BaseCacheManager manager,
    _IllustrationCacheState state,
    int generation,
    String url,
    Future<List<int>> Function() load,
  ) async {
    await state.mutations;
    try {
      final cached = await manager.getFileFromCache(url);
      if (cached != null && cached.validTill.isAfter(DateTime.now())) {
        final bytes = await cached.file.readAsBytes();
        await _validateImage(bytes);
        return bytes;
      }
    } catch (error, stack) {
      _recordWarning(error, stack, 'read');
      final removal = state.mutations.then((_) async {
        if (generation != state.generation) return;
        try {
          await manager.removeFile(url);
        } catch (error, stack) {
          _recordWarning(error, stack, 'remove');
        }
      });
      state.mutations = removal;
      await removal;
    }

    final loaded = await load();
    final bytes = loaded is Uint8List ? loaded : Uint8List.fromList(loaded);
    try {
      await _validateImage(bytes);
    } catch (error, stack) {
      _recordWarning(error, stack, 'validate');
      rethrow;
    }

    final write = state.mutations.then((_) async {
      // 清理期间尚未完成的请求仍能显示，但不能把已清理的缓存写回来。
      if (generation != state.generation) return;
      try {
        await manager.putFile(url, bytes, key: url, maxAge: _ttl);
      } catch (error, stack) {
        _recordWarning(error, stack, 'write');
      }
    });
    state.mutations = write;
    await write;
    return bytes;
  }

  /// 仅验证编码尺寸，不解码/持有完整像素；无效内容不会进入磁盘缓存。
  static Future<void> _validateImage(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (descriptor.width <= 0 || descriptor.height <= 0) {
          throw const FormatException('Invalid illustration dimensions');
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }

  /// 串行清空磁盘；后续读取等待清理完成，并不影响永久下载。
  /// 清理失败保留原始异常给缓存管理页，同时记录真实堆栈。
  Future<void> clear() {
    final manager = _manager;
    final state = _stateFor(manager);
    state.generation++;
    state.inFlight.clear();
    final clearing = state.mutations.then((_) => manager.emptyCache());
    state.mutations = clearing.catchError((Object error, StackTrace stack) {
      _recordWarning(error, stack, 'clear');
    });
    return clearing;
  }

  static void _recordWarning(Object error, StackTrace stack, String operation) {
    unawaited(
      AppLogger.instance.recordWarning(
        error,
        stackTrace: stack,
        source: 'novel_illustration_cache.$operation',
      ),
    );
  }
}

class _IllustrationCacheState {
  final inFlight = <String, Future<List<int>>>{};
  Future<void> mutations = Future<void>.value();
  int generation = 0;
}
