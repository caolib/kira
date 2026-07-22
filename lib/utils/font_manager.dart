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

  /// Combined catalog: remote fonts first, then user-added custom fonts.
  /// Custom entries override remote ones with the same name.
  List<RemoteFontInfo> get cachedList =>
      _mergedFontList(_remoteList, _customList);

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
          .where((font) => font.name.isNotEmpty && font.url.isNotEmpty)
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
          .where((font) => font.name.isNotEmpty && font.url.isNotEmpty)
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

  /// Loads the font list with a 3-day persistent cache strategy:
  /// - Returns the in-memory catalog after the first attempt in this process.
  /// - Uses valid persistent data without requesting the remote catalog.
  /// - If cached data is missing or expired, fetches and updates the cache.
  /// - [force] always requests fresh data, with valid cache as a fallback.
  /// User-added custom fonts are always merged into the result.
  Future<List<RemoteFontInfo>> fetchAvailableFonts({bool force = false}) async {
    await _ensureCustomFontsLoaded();

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

  /// Test-only: clear in-memory state so prefs can be re-read.
  void resetForTest() {
    _remoteList = const [];
    _remoteListLoaded = false;
    _customList = const [];
    _customFontsLoaded = false;
    _fontDir = null;
    _dirInitialized = false;
  }
}
