import 'backup_error.dart';

class WebDavConfig {
  final Uri server;
  final List<String> directorySegments;
  final bool allowHttp;

  WebDavConfig._(this.server, this.directorySegments, this.allowHttp);

  /// [directory] is optional: an empty value stores backups in the server
  /// root instead of a subfolder.
  factory WebDavConfig({
    required String serverUrl,
    String directory = '',
    bool allowHttp = false,
  }) {
    final text = serverUrl.trim();
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (text.isEmpty ||
        uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !safeSegments(uri.pathSegments)) {
      throw const WebDavException(WebDavErrorCode.invalidConfiguration);
    }
    if (uri.scheme == 'http' && !allowHttp) {
      throw const WebDavException(WebDavErrorCode.httpNotAllowed);
    }
    final parts = directory
        .trim()
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();
    if (!safeSegments(parts)) {
      throw const WebDavException(WebDavErrorCode.invalidConfiguration);
    }
    return WebDavConfig._(
      uri.replace(
        pathSegments: [...uri.pathSegments.where((s) => s.isNotEmpty), ''],
      ),
      List.unmodifiable(parts),
      allowHttp && uri.scheme == 'http',
    );
  }

  String get directory =>
      directorySegments.isEmpty ? '' : '${directorySegments.join('/')}/';
  List<String> get rootSegments => [
    ...server.pathSegments.where((s) => s.isNotEmpty),
    ...directorySegments,
  ];
  Uri get root => server.replace(pathSegments: [...rootSegments, '']);

  Uri fileUri(String name) {
    if (name.isEmpty || !safeSegments([name])) {
      throw const WebDavException(WebDavErrorCode.unsafePath);
    }
    return server.replace(pathSegments: [...rootSegments, name]);
  }

  bool sameOrigin(Uri uri) =>
      uri.scheme == server.scheme &&
      uri.host == server.host &&
      uri.port == server.port &&
      uri.userInfo.isEmpty;

  /// Reject decoded separators, dot segments, control characters and nested
  /// percent encoding. Uri.pathSegments already decodes ordinary UTF-8 hrefs.
  static bool safeSegments(Iterable<String> segments) => segments.every(
    (part) =>
        part != '.' &&
        part != '..' &&
        !RegExp(r'[/\\%?#\x00-\x1f\x7f]').hasMatch(part),
  );
}

class WebDavCredentials {
  final String username;
  final String password;

  const WebDavCredentials({required this.username, required this.password});
}

class WebDavBackupEntry {
  final String name;
  final int? size;
  final DateTime? modified;

  const WebDavBackupEntry({required this.name, this.size, this.modified});

  bool get encrypted => name.toLowerCase().endsWith('.kirabak');

  static bool isBackupName(String name) {
    final normalized = name.toLowerCase();
    return name.isNotEmpty &&
        WebDavConfig.safeSegments([name]) &&
        (normalized.endsWith('.kirabak') ||
            normalized.endsWith('.json.gz') ||
            normalized.endsWith('.json'));
  }
}

enum WebDavErrorCode {
  invalidConfiguration,
  httpNotAllowed,
  authentication,
  forbidden,
  notFound,
  moveUnsupported,
  methodUnsupported,
  redirectRefused,
  unsafePath,
  invalidResponse,
  connection,
  timeout,
  conflict,
}

class WebDavException implements Exception {
  final WebDavErrorCode code;
  final int? status;

  const WebDavException(this.code, {this.status});

  @override
  String toString() => 'WebDavException(${code.name}, $status)';
}

Never backupCancelled() =>
    throw const SettingsBackupException(SettingsBackupErrorCode.cancelled);
