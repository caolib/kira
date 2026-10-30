import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';
import 'app_storage.dart';
import 'json_helpers.dart';

/// Metadata for a downloadable remote font.
class RemoteFontInfo {
  final String name;
  final String url;
  final bool isCustom;

  const RemoteFontInfo({
    required this.name,
    required this.url,
    this.isCustom = false,
  });

  factory RemoteFontInfo.fromJson(
    Map<String, dynamic> json, {
    bool isCustom = false,
  }) {
    return RemoteFontInfo(
      name: jsonString(json, 'name'),
      url: jsonString(json, 'url'),
      isCustom: isCustom || jsonBool(json, 'is_custom'),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    if (isCustom) 'is_custom': true,
  };

  RemoteFontInfo copyWith({String? name, String? url, bool? isCustom}) {
    return RemoteFontInfo(
      name: name ?? this.name,
      url: url ?? this.url,
      isCustom: isCustom ?? this.isCustom,
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
  static const fontListCacheTtl = Duration(days: 3);
  static const _cacheKey = 'font_list_v1';
  static const _customFontsPrefsKey = 'custom_fonts_v1';

  /// The font family name to use when no custom font is selected.
  static const defaultFontId = 'system';

  List<RemoteFontInfo> _remoteList = const [];
  bool _remoteListLoaded = false;
  List<RemoteFontInfo> _customList = const [];
  bool _customFontsLoaded = false;
  List<RemoteFontInfo> _downloadedList = const [];

  /// Combined catalog: remote fonts first, then user-added custom fonts.
  /// Custom entries override remote ones with the same name.
  ///
  /// Fonts already downloaded to local storage are appended even when the
  /// remote catalog no longer lists them, so a downloaded font never becomes
  /// unselectable. Such entries carry an empty [RemoteFontInfo.url].
  List<RemoteFontInfo> get cachedList {
    final merged = _mergedFontList(_remoteList, _customList);
    final known = merged.map((font) => font.name).toSet();
    return [
      ...merged,
      ..._downloadedList.where((font) => !known.contains(font.name)),
    ];
  }

  List<RemoteFontInfo> get customFonts => List.unmodifiable(_customList);

  List<RemoteFontInfo> _parseFontList(dynamic data, {bool isCustom = false}) {
    if (data is Map<String, dynamic> && data['fonts'] is List) {
      return (data['fonts'] as List)
          .whereType<Map>()
          .map(
            (entry) => RemoteFontInfo.fromJson(
              Map<String, dynamic>.from(entry),
              isCustom: isCustom,
            ),
          )
          .where(
            (font) => font.name.isNotEmpty && (font.url.isNotEmpty || isCustom),
          )
          .toList();
    }
    if (data is List) {
      return data
          .whereType<Map>()
          .map(
            (entry) => RemoteFontInfo.fromJson(
              Map<String, dynamic>.from(entry),
              isCustom: isCustom,
            ),
          )
          .where(
            (font) => font.name.isNotEmpty && (font.url.isNotEmpty || isCustom),
          )
          .toList();
    }
    return const [];
  }

  List<RemoteFontInfo> _mergedFontList(
    List<RemoteFontInfo> remoteFonts,
    List<RemoteFontInfo> customFonts,
  ) {
    final byName = <String, RemoteFontInfo>{};
    for (final font in remoteFonts) {
      byName[font.name] = font;
    }
    for (final font in customFonts) {
      byName[font.name] = font;
    }
    return byName.values.toList();
  }

  Future<void> _ensureCustomFontsLoaded() async {
    if (_customFontsLoaded) return;
    final raw = await AppStorage.preferences.getJson(_customFontsPrefsKey);
    _customList = _parseFontList(
      raw,
      isCustom: true,
    ).map((font) => font.copyWith(isCustom: true)).toList();
    _customFontsLoaded = true;
  }

  Future<void> _persistCustomFonts() async {
    await AppStorage.preferences.setJson(
      _customFontsPrefsKey,
      _customList.map((font) => font.toJson()).toList(),
    );
  }

  /// Rescans the local font directory so downloaded fonts that disappeared
  /// from the remote catalog still show up in the picker.
  Future<void> _refreshDownloadedList() async {
    try {
      final names = await listDownloadedFonts();
      _downloadedList = names
          .where((name) => name.isNotEmpty && name != defaultFontId)
          .map((name) => RemoteFontInfo(name: name, url: ''))
          .toList(growable: false);
    } catch (error, stackTrace) {
      // path_provider may be unavailable (tests); the catalog stays usable.
      await AppLogger.instance.recordWarning(error, stackTrace: stackTrace);
      _downloadedList = const [];
    }
  }

  /// Loads the font list with a 3-day persistent cache strategy:
  /// - Returns the in-memory catalog after the first attempt in this process.
  /// - Uses valid persistent data without requesting the remote catalog.
  /// - If cached data is missing or expired, fetches and updates the cache.
  /// - [force] always requests fresh data, with valid cache as a fallback.
  /// User-added custom fonts are always merged into the result.
  Future<List<RemoteFontInfo>> fetchAvailableFonts({bool force = false}) async {
    await _ensureCustomFontsLoaded();
    await _refreshDownloadedList();

    if (!force && _remoteListLoaded) {
      return cachedList;
    }

    final cached = await AppStorage.cache.get(_cacheKey);

    if (!force && cached != null) {
      final fonts = _parseFontList(cached);
      if (fonts.isNotEmpty) {
        _remoteList = fonts;
        _remoteListLoaded = true;
        return cachedList;
      }
    }

    final fresh = await _fetchFromRemote();
    if (fresh.isNotEmpty) {
      _remoteList = fresh;
      await AppStorage.cache.put(_cacheKey, {
        'fonts': fresh.map((font) => font.toJson()).toList(),
      }, ttl: fontListCacheTtl);
    } else if (cached != null) {
      final fonts = _parseFontList(cached);
      _remoteList = fonts;
      _remoteListLoaded = true;
      return cachedList;
    }

    _remoteListLoaded = true;
    return cachedList;
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

      final json = jsonDecode(utf8.decode(body));
      if (json is Map<String, dynamic>) {
        return _parseFontList(json);
      }
      return const [];
    } catch (e, stack) {
      await AppLogger.instance.recordError(
        e,
        stackTrace: stack,
        source: 'font_list_fetch',
      );
      return const [];
    }
  }

  /// Looks up a font by name from the merged catalog (remote + custom).
  RemoteFontInfo? infoForName(String name) {
    for (final font in cachedList) {
      if (font.name == name) return font;
    }
    return null;
  }

  /// Adds or updates a user-defined font (name + download URL).
  ///
  /// Returns `false` when [name] or [url] is empty, or [url] is not a valid
  /// absolute HTTP(S) URI.
  Future<bool> addCustomFont({
    required String name,
    required String url,
  }) async {
    final trimmedName = name.trim();
    final trimmedUrl = url.trim();
    if (trimmedName.isEmpty || trimmedUrl.isEmpty) return false;
    if (trimmedName == defaultFontId) return false;

    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null ||
        !uri.hasScheme ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return false;
    }

    await _ensureCustomFontsLoaded();

    final entry = RemoteFontInfo(
      name: trimmedName,
      url: trimmedUrl,
      isCustom: true,
    );
    final existingIndex = _customList.indexWhere(
      (font) => font.name == trimmedName,
    );
    if (existingIndex >= 0) {
      _customList = List<RemoteFontInfo>.from(_customList)
        ..[existingIndex] = entry;
    } else {
      _customList = [..._customList, entry];
    }
    await _persistCustomFonts();
    return true;
  }

  /// Imports a user-picked local font file into the managed font directory.
  ///
  /// The font is registered as a custom entry without a download URL, using
  /// [name] (the file name without its extension) as its family name.
  ///
  /// Returns `false` when [name] is unusable, the bytes are not a supported
  /// font file, or writing to disk fails.
  Future<bool> importLocalFont({
    required String name,
    required Uint8List bytes,
  }) async {
    final trimmedName = _sanitizeFontName(name);
    if (trimmedName.isEmpty || trimmedName == defaultFontId) return false;
    if (!_looksLikeFontFile(bytes)) return false;

    try {
      await File(
        await fontFilePath(trimmedName),
      ).writeAsBytes(bytes, flush: true);
    } catch (error, stackTrace) {
      await AppLogger.instance.recordError(
        error,
        stackTrace: stackTrace,
        source: 'font_import',
      );
      return false;
    }

    await _ensureCustomFontsLoaded();
    final entry = RemoteFontInfo(name: trimmedName, url: '', isCustom: true);
    final existingIndex = _customList.indexWhere(
      (font) => font.name == trimmedName,
    );
    if (existingIndex >= 0) {
      _customList = List<RemoteFontInfo>.from(_customList)
        ..[existingIndex] = entry;
    } else {
      _customList = [..._customList, entry];
    }
    await _persistCustomFonts();

    if (!_downloadedList.any((font) => font.name == trimmedName)) {
      _downloadedList = [
        ..._downloadedList,
        RemoteFontInfo(name: trimmedName, url: ''),
      ];
    }
    return true;
  }

  /// Strips characters that cannot appear in a portable file name.
  String _sanitizeFontName(String name) {
    return name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Recognises the SFNT/OpenType signatures Flutter's FontLoader accepts.
  bool _looksLikeFontFile(List<int> bytes) {
    if (bytes.length < 4) return false;
    final signature =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return signature == 0x00010000 || // TrueType outlines
        signature == 0x4F54544F || // 'OTTO' (CFF outlines)
        signature == 0x74727565 || // 'true' (legacy Apple)
        signature == 0x74746366 || // 'ttcf' (TrueType collection)
        signature == 0x74797031; // 'typ1'
  }

  /// Removes a user-defined font entry and its local file (if present).
  Future<void> removeCustomFont(String fontName) async {
    if (fontName.isEmpty || fontName == defaultFontId) return;
    await _ensureCustomFontsLoaded();
    final beforeCount = _customList.length;
    _customList = _customList
        .where((font) => font.name != fontName)
        .toList(growable: false);
    if (_customList.length != beforeCount) {
      await _persistCustomFonts();
    }
    try {
      await deleteFont(fontName);
    } catch (error, stackTrace) {
      // Local file cleanup is best-effort (e.g. missing path_provider in tests).
      await AppLogger.instance.recordWarning(error, stackTrace: stackTrace);
    }
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
      if (!_downloadedList.any((entry) => entry.name == font.name)) {
        _downloadedList = [
          ..._downloadedList,
          RemoteFontInfo(name: font.name, url: ''),
        ];
      }
      return true;
    } catch (e, stack) {
      if (await outFile.exists()) {
        try {
          await outFile.delete();
        } catch (deleteError, deleteStack) {
          await AppLogger.instance.recordWarning(
            deleteError,
            stackTrace: deleteStack,
          );
        }
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
  Future<String?> loadFont(
    String fontName, {
    bool rethrowErrors = false,
  }) async {
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
      if (rethrowErrors) rethrow;
      return null;
    }
  }

  /// Convenience method: download (if needed) then load a font.
  Future<String?> ensureFontReady(String fontName) async {
    if (fontName.isEmpty || fontName == defaultFontId) return null;

    await _ensureCustomFontsLoaded();

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
    _downloadedList = _downloadedList
        .where((font) => font.name != fontName)
        .toList(growable: false);
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

  /// 丢弃内存缓存(字体目录、远端目录、自定义字体列表)。
  ///
  /// 导入备份 / 清除数据后调用,或测试中在 `setMockInitialValues` 之后强制
  /// 下次从新的 prefs 重读。
  void reloadFromPrefs() {
    _remoteList = const [];
    _remoteListLoaded = false;
    _customList = const [];
    _customFontsLoaded = false;
    _downloadedList = const [];
    _fontDir = null;
    _dirInitialized = false;
  }
}
