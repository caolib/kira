import 'dart:convert';

import 'package:dio/dio.dart';

import '../utils/app_dio.dart';
import '../utils/json_helpers.dart';

/// Kira 远程高级设置配置（当前只提供 COPY versionCode）。
///
/// 文件由 notice 仓库维护，发布在 CDN 静态路径上；请求带时间戳与
/// no-cache 头，避免 CDN 缓存导致发布后长时间不生效。
class CopySettingsRemote {
  CopySettingsRemote({Dio? dio, this.settingsUrl = defaultSettingsUrl})
    : _dio = dio ?? _defaultDio;

  static const defaultSettingsUrl =
      'https://cdn.caolib.qzz.io/kira/copy-settings.json';

  static final Dio _defaultDio = AppDio.create(
    source: 'copy_settings',
    options: BaseOptions(
      headers: const {'Accept': 'application/json', 'User-Agent': 'Kira-App'},
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  final Dio _dio;
  final String settingsUrl;

  /// 拉取远端 versionCode；字段缺失或非法时返回 null，调用方保留旧值。
  Future<String?> fetchVersionCode() async {
    final uri = Uri.tryParse(settingsUrl.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return null;

    final response = await _dio.getUri<Object?>(
      uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          '_t': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      ),
      options: Options(
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      ),
    );
    final data = _decode(response.data);
    if (data == null) return null;

    final raw = jsonString(
      data,
      'version_code',
      fallback: jsonString(data, 'versionCode'),
    ).trim();
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty || digits.length > 10) return null;
    return digits;
  }

  Map<String, dynamic>? _decode(Object? data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
