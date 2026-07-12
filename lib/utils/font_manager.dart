import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';
import 'app_storage.dart';

/// Metadata for a downloadable remote font.
class RemoteFontInfo {
  final String name;
  final String url;

  const RemoteFontInfo({required this.name, required this.url});

  factory RemoteFontInfo.fromJson(Map<String, dynamic> json) {
    return RemoteFontInfo(
      name: json['name'] as String,
      url: json['url'] as String,
    );
  }
}

/// Manages downloading remote fonts to local storage and dynamically loading
/// them into the Flutter engine so the UI can switch fonts at runtime.
class FontManager {
  FontManager._();
  static final FontManager _instance = FontManager._();
  factory FontManager() => _instance;

  static const fontListUrl = 'https://cdn.caolib.qzz.io/fonts/list.json';
  static const _cacheKey = 'font_list_v1';
  static const _cacheTtl = Duration(hours: 6);

  /// The font family name to use when no custom font is selected.
  static const defaultFontId = 'system';

  List<RemoteFontInfo> _cachedList = const [];
  List<RemoteFontInfo> get cachedList => _cachedList;

  List<RemoteFontInfo> _parseFontList(dynamic data) {
    if (data is Map<String, dynamic> && data['fonts'] is List) {
      return (data['fonts'] as List)
          .map((e) => RemoteFontInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return const [];
  }

  /// Loads the font list with a 6-hour persistent cache strategy:
  /// - Always returns cached data immediately if available (even if stale).
  /// - If cached data is missing or expired, fetches from remote and updates cache.
  /// - [force] bypasses cache entirely for a fresh fetch.
  Future<List<RemoteFontInfo>> fetchAvailableFonts({bool force = false}) async {
    if (!force && _cachedList.isNotEmpty) return _cachedList;

    final cached = await AppStorage.cache.get(_cacheKey);

    if (!force && cached != null) {
      final fonts = _parseFontList(cached);
      if (fonts.isNotEmpty) {
        _cachedList = fonts;
        return fonts;
      }
    }

    final fresh = await _fetchFromRemote();
    if (fresh.isNotEmpty) {
      _cachedList = fresh;
      await AppStorage.cache.put(_cacheKey, {
        'fonts': fresh.map((f) => {'name': f.name, 'url': f.url}).toList(),
      }, ttl: _cacheTtl);
    } else if (cached != null) {
      final fonts = _parseFontList(cached);
      _cachedList = fonts;
      return fonts;
    }

    return _cachedList;
  }

  Future<List<RemoteFontInfo>> _fetchFromRemote() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(fontListUrl));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final body = <int>[];
      await for (final chunk in response) {
        body.addAll(chunk);
      }
      client.close();

      final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      return _parseFontList(json);
    } catch (e, stack) {
      await AppLogger.instance.recordError(
        e,
        stackTrace: stack,
        source: 'font_list_fetch',
      );
      return const [];
    }
  }

  /// Looks up a font by name from the cached list.
  RemoteFontInfo? infoForName(String name) {
    for (final f in _cachedList) {
      if (f.name == name) return f;
    }
    return null;
  }

  Directory? _fontDir;
  bool _dirInitialized = false;

  Future<Directory> _getFontDir() async {
    if (_dirInitialized && _fontDir != null) return _fontDir!;
    final support = await getApplicationSupportDirectory();
    _fontDir = Directory('${support.path}${Platform.pathSeparator}fonts');
    if (!await _fontDir!.exists()) {
      await _fontDir!.create(recursive: true);
    }
    _dirInitialized = true;
    return _fontDir!;
  }

  /// Returns the local file path for a given font name.
  Future<String> fontFilePath(String fontName) async {
    final dir = await _getFontDir();
    return '${dir.path}${Platform.pathSeparator}$fontName.ttf';
  }

  /// Checks if a font has been downloaded to local storage.
  Future<bool> isFontDownloaded(String fontName) async {
    if (fontName.isEmpty || fontName == defaultFontId) return true;
    final path = await fontFilePath(fontName);
    final file = File(path);
    return file.exists();
  }

  /// Downloads a remote font to local storage.
  Future<bool> downloadFont(RemoteFontInfo font) async {
    final outPath = await fontFilePath(font.name);
    final outFile = File(outPath);

    if (await outFile.exists()) return true;

    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(font.url));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      await outFile.writeAsBytes(bytes);
      client.close();
      return true;
    } catch (e, stack) {
      if (await outFile.exists()) {
        try {
          await outFile.delete();
        } catch (_) {}
      }
      await AppLogger.instance.recordError(
        e,
        stackTrace: stack,
        source: 'font_download',
      );
      return false;
    }
  }

  /// Loads a downloaded font file into the Flutter engine by its name.
  Future<String?> loadFont(String fontName) async {
    if (fontName.isEmpty || fontName == defaultFontId) return null;

    final path = await fontFilePath(fontName);
    final file = File(path);

    if (!await file.exists()) return null;

    try {
      final bytes = await file.readAsBytes();
      final byteData = ByteData.sublistView(bytes);

      final fontLoader = FontLoader(fontName);
      fontLoader.addFont(Future.value(byteData));
      await fontLoader.load();

      return fontName;
    } catch (e, stack) {
      await AppLogger.instance.recordError(
        e,
        stackTrace: stack,
        source: 'font_load',
      );
      debugPrint('FontManager: failed to load font "$fontName": $e');
      return null;
    }
  }

  /// Convenience method: download (if needed) then load a font.
  Future<String?> ensureFontReady(String fontName) async {
    if (fontName.isEmpty || fontName == defaultFontId) return null;

    final isDownloaded = await isFontDownloaded(fontName);
    if (!isDownloaded) {
      final font = infoForName(fontName);
      if (font == null) return null;
      final ok = await downloadFont(font);
      if (!ok) return null;
    }

    return loadFont(fontName);
  }

  /// Deletes a downloaded font from local storage.
  Future<void> deleteFont(String fontName) async {
    if (fontName.isEmpty || fontName == defaultFontId) return;
    final path = await fontFilePath(fontName);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Lists all downloaded font names from local storage.
  Future<List<String>> listDownloadedFonts() async {
    final dir = await _getFontDir();
    final result = <String>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.ttf')) {
        final name = entity.uri.pathSegments.last;
        result.add(name.substring(0, name.length - 4));
      }
    }
    return result;
  }
}
