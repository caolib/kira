import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef AppLogDirectoryProvider = Future<Directory> Function();

enum AppLogLevel {
  debug,
  info,
  warning,
  error;

  String get displayName {
    return switch (this) {
      AppLogLevel.debug => '调试',
      AppLogLevel.info => '信息',
      AppLogLevel.warning => '警告',
      AppLogLevel.error => '错误',
    };
  }

  String get thresholdLabel => displayName;

  int get severity {
    return switch (this) {
      AppLogLevel.debug => 0,
      AppLogLevel.info => 1,
      AppLogLevel.warning => 2,
      AppLogLevel.error => 3,
    };
  }

  bool isAtLeast(AppLogLevel minimumLevel) {
    return severity >= minimumLevel.severity;
  }

  static AppLogLevel fromName(
    String? name, {
    AppLogLevel fallback = AppLogLevel.error,
  }) {
    return AppLogLevel.values.firstWhere(
      (level) => level.name == name,
      orElse: () => fallback,
    );
  }
}

class AppLogEntry {
  const AppLogEntry({
    required this.timestamp,
    required this.level,
    required this.source,
    required this.message,
    this.stackTrace,
    this.context = const {},
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String source;
  final String message;
  final String? stackTrace;
  final Map<String, String> context;

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toUtc().toIso8601String(),
      'level': level.name,
      'source': source,
      'message': message,
      if (stackTrace != null && stackTrace!.isNotEmpty)
        'stackTrace': stackTrace,
      if (context.isNotEmpty) 'context': context,
    };
  }

  factory AppLogEntry.fromJson(Map<String, dynamic> json) {
    final timestamp = DateTime.tryParse(json['timestamp']?.toString() ?? '');
    final contextJson = json['context'];
    final context = <String, String>{};
    if (contextJson is Map) {
      for (final entry in contextJson.entries) {
        context[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }

    return AppLogEntry(
      timestamp:
          timestamp ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      level: AppLogLevel.fromName(json['level']?.toString()),
      source: json['source']?.toString() ?? 'app',
      message: json['message']?.toString() ?? '',
      stackTrace: json['stackTrace']?.toString(),
      context: context,
    );
  }

  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln('time: ${timestamp.toLocal().toIso8601String()}')
      ..writeln('level: ${level.name}')
      ..writeln('source: $source')
      ..writeln('message: $message');

    if (context.isNotEmpty) {
      buffer.writeln('context:');
      for (final entry in context.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    }

    final stackTrace = this.stackTrace;
    if (stackTrace != null && stackTrace.isNotEmpty) {
      buffer
        ..writeln('stackTrace:')
        ..write(stackTrace);
    }

    return buffer.toString().trimRight();
  }
}

class AppLogger {
  AppLogger({
    AppLogDirectoryProvider? directoryProvider,
    this.maxFileSizeBytes = 1024 * 1024,
    this.maxRotatedFiles = 3,
  }) : _directoryProvider = directoryProvider ?? _defaultLogDirectory {
    assert(maxFileSizeBytes > 0);
    assert(maxRotatedFiles >= 0);
  }

  static final AppLogger instance = AppLogger();

  static const _currentLogFileName = 'error.log';
  static const _keyLoggingEnabled = 'app_logging_enabled';
  static const _keyMinimumLevel = 'app_logging_minimum_level';
  static const defaultLoggingEnabled = true;
  static const defaultMinimumLevel = AppLogLevel.warning;
  static const _maxMessageLength = 4000;
  static const _maxStackTraceLength = 12000;
  static const _maxContextValueLength = 2000;
  static const _redacted = '[REDACTED]';

  static final _sensitiveKeyPattern = RegExp(
    r'^(authorization|token|access_token|refresh_token|password|passwd|cookie|set-cookie)$',
    caseSensitive: false,
  );
  static final _authorizationBearerPattern = RegExp(
    r'''\b(authorization\b\s*[:=]\s*)bearer\s+[^"',;\s}&]+''',
    caseSensitive: false,
  );
  static final _sensitiveValuePattern = RegExp(
    r'''\b(authorization|token|access_token|refresh_token|password|passwd|cookie|set-cookie)\b(\s*[:=]\s*)["']?([^"',;\s}&]+)["']?''',
    caseSensitive: false,
  );

  final AppLogDirectoryProvider _directoryProvider;
  final int maxFileSizeBytes;
  final int maxRotatedFiles;

  Directory? _directory;
  Future<void>? _initFuture;
  Future<void> _writeQueue = Future<void>.value();
  bool _disabled = false;
  bool _loggingEnabled = defaultLoggingEnabled;
  AppLogLevel _minimumLevel = defaultMinimumLevel;

  bool get loggingEnabled => _loggingEnabled;
  AppLogLevel get minimumLevel => _minimumLevel;

  Future<void> init() {
    if (_disabled) return Future<void>.value();
    return _initFuture ??= _init().catchError((Object error, StackTrace stack) {
      _disabled = true;
      debugPrint('AppLogger init failed: $error');
    });
  }

  Future<void> recordFlutterError(FlutterErrorDetails details) {
    final information = _collectFlutterInformation(details);
    return recordError(
      details.exception,
      stackTrace: details.stack,
      source: 'flutter',
      context: {
        if (details.library != null) 'library': details.library,
        if (details.context != null)
          'context': details.context!.toDescription(),
        if (information.isNotEmpty) 'information': information,
      },
    );
  }

  Future<void> recordError(
    Object error, {
    StackTrace? stackTrace,
    String source = 'app',
    Map<String, Object?>? context,
  }) {
    return record(
      error,
      level: AppLogLevel.error,
      stackTrace: stackTrace,
      source: source,
      context: context,
    );
  }

  Future<void> recordWarning(
    Object message, {
    StackTrace? stackTrace,
    String source = 'app',
    Map<String, Object?>? context,
  }) {
    return record(
      message,
      level: AppLogLevel.warning,
      stackTrace: stackTrace,
      source: source,
      context: context,
    );
  }

  Future<void> recordInfo(
    Object message, {
    StackTrace? stackTrace,
    String source = 'app',
    Map<String, Object?>? context,
  }) {
    return record(
      message,
      level: AppLogLevel.info,
      stackTrace: stackTrace,
      source: source,
      context: context,
    );
  }

  Future<void> recordDebug(
    Object message, {
    StackTrace? stackTrace,
    String source = 'app',
    Map<String, Object?>? context,
  }) {
    return record(
      message,
      level: AppLogLevel.debug,
      stackTrace: stackTrace,
      source: source,
      context: context,
    );
  }

  Future<void> record(
    Object message, {
    required AppLogLevel level,
    StackTrace? stackTrace,
    String source = 'app',
    Map<String, Object?>? context,
  }) {
    _writeQueue = _writeQueue
        .then((_) async {
          await _ensureReady();
          if (!_shouldRecord(level)) return;
          final entry = AppLogEntry(
            timestamp: DateTime.now().toUtc(),
            level: level,
            source: _truncate(_redact(source), _maxContextValueLength),
            message: _truncate(
              _redact(_safeToString(message)),
              _maxMessageLength,
            ),
            stackTrace: stackTrace == null
                ? null
                : _truncate(
                    _redact(stackTrace.toString()),
                    _maxStackTraceLength,
                  ),
            context: _sanitizeContext(context),
          );
          await _writeEntry(entry);
        })
        .catchError((Object writeError, StackTrace stack) {
          debugPrint('AppLogger write failed: $writeError');
        });

    return _writeQueue;
  }

  Future<void> setLoggingEnabled(bool enabled) async {
    _loggingEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLoggingEnabled, enabled);
    } catch (error) {
      debugPrint('AppLogger save logging enabled failed: $error');
    }
  }

  Future<void> setMinimumLevel(AppLogLevel level) async {
    _minimumLevel = level;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMinimumLevel, level.name);
    } catch (error) {
      debugPrint('AppLogger save minimum level failed: $error');
    }
  }

  Future<List<AppLogEntry>> readEntries({int limit = 200}) async {
    await _ensureReady();
    await _writeQueue;

    final directory = _directory;
    if (_disabled || directory == null || !await directory.exists()) {
      return const [];
    }

    final entries = <AppLogEntry>[];
    for (final file in _logFiles(directory)) {
      if (!await file.exists()) continue;
      final lines = await file.readAsLines();
      for (final line in lines.reversed) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final json = jsonDecode(trimmed);
          if (json is Map<String, dynamic>) {
            entries.add(AppLogEntry.fromJson(json));
            if (entries.length >= limit) return entries;
          }
        } catch (_) {
          continue;
        }
      }
    }

    return entries;
  }

  Future<String> exportText({int limit = 200}) async {
    final entries = await readEntries(limit: limit);
    return entries.map((entry) => entry.toPlainText()).join('\n\n---\n\n');
  }

  Future<void> clear() async {
    await _ensureReady();
    await _writeQueue;

    final directory = _directory;
    if (_disabled || directory == null || !await directory.exists()) return;

    await Future.wait(
      _logFiles(
        directory,
      ).where((file) => file.existsSync()).map((file) => file.delete()),
    );
  }

  Future<void> _init() async {
    await _loadSettings();
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _directory = directory;
  }

  Future<void> _ensureReady() async {
    if (_disabled) return;
    await init();
  }

  Future<void> _writeEntry(AppLogEntry entry) async {
    await _ensureReady();

    final directory = _directory;
    if (_disabled || directory == null) return;
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final line = jsonEncode(entry.toJson());
    final additionalBytes = utf8.encode('$line\n').length;
    await _rotateIfNeeded(directory, additionalBytes);
    await _currentLogFile(
      directory,
    ).writeAsString('$line\n', mode: FileMode.append, flush: true);
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _loggingEnabled =
          prefs.getBool(_keyLoggingEnabled) ?? defaultLoggingEnabled;
      _minimumLevel = AppLogLevel.fromName(
        prefs.getString(_keyMinimumLevel),
        fallback: defaultMinimumLevel,
      );
    } catch (error) {
      debugPrint('AppLogger load settings failed: $error');
    }
  }

  bool _shouldRecord(AppLogLevel level) {
    return !_disabled && _loggingEnabled && level.isAtLeast(_minimumLevel);
  }

  Future<void> _rotateIfNeeded(Directory directory, int additionalBytes) async {
    final current = _currentLogFile(directory);
    if (!await current.exists()) return;

    final currentLength = await current.length();
    if (currentLength + additionalBytes <= maxFileSizeBytes) return;

    if (maxRotatedFiles == 0) {
      await current.delete();
      return;
    }

    for (var index = maxRotatedFiles; index >= 1; index--) {
      final file = _rotatedLogFile(directory, index);
      if (!await file.exists()) continue;

      if (index == maxRotatedFiles) {
        await file.delete();
      } else {
        final next = _rotatedLogFile(directory, index + 1);
        if (await next.exists()) {
          await next.delete();
        }
        await file.rename(next.path);
      }
    }

    final firstRotated = _rotatedLogFile(directory, 1);
    if (await firstRotated.exists()) {
      await firstRotated.delete();
    }
    await current.rename(firstRotated.path);
  }

  Iterable<File> _logFiles(Directory directory) sync* {
    yield _currentLogFile(directory);
    for (var index = 1; index <= maxRotatedFiles; index++) {
      yield _rotatedLogFile(directory, index);
    }
  }

  File _currentLogFile(Directory directory) {
    return File(
      '${directory.path}${Platform.pathSeparator}$_currentLogFileName',
    );
  }

  File _rotatedLogFile(Directory directory, int index) {
    return File('${directory.path}${Platform.pathSeparator}error.$index.log');
  }

  static Future<Directory> _defaultLogDirectory() async {
    Directory baseDirectory;
    try {
      baseDirectory = await getApplicationSupportDirectory();
    } catch (_) {
      baseDirectory = await getApplicationDocumentsDirectory();
    }
    return Directory('${baseDirectory.path}${Platform.pathSeparator}logs');
  }

  static Map<String, String> _sanitizeContext(Map<String, Object?>? context) {
    if (context == null || context.isEmpty) return const {};

    final sanitized = <String, String>{};
    for (final entry in context.entries) {
      final key = _truncate(_redact(entry.key), _maxContextValueLength);
      final rawValue = entry.value?.toString() ?? '';
      final value = _sensitiveKeyPattern.hasMatch(entry.key)
          ? _redacted
          : _truncate(_redact(rawValue), _maxContextValueLength);
      if (key.isNotEmpty && value.isNotEmpty) {
        sanitized[key] = value;
      }
    }
    return sanitized;
  }

  static String _collectFlutterInformation(FlutterErrorDetails details) {
    final collector = details.informationCollector;
    if (collector == null) return '';

    try {
      final information = collector()
          .map((node) => node.toStringDeep())
          .where((line) => line.trim().isNotEmpty)
          .join('\n')
          .trim();
      return information;
    } catch (_) {
      return '';
    }
  }

  static String _safeToString(Object value) {
    try {
      return value.toString();
    } catch (_) {
      return value.runtimeType.toString();
    }
  }

  static String _redact(String value) {
    return value
        .replaceAllMapped(_authorizationBearerPattern, (match) {
          return '${match.group(1)}$_redacted';
        })
        .replaceAllMapped(_sensitiveValuePattern, (match) {
          return '${match.group(1)}${match.group(2)}$_redacted';
        });
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...';
  }
}
