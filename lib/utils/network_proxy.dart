import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:native_flutter_proxy/native_flutter_proxy.dart';

import '../models/user_manager.dart';

class NetworkProxyEndpoint {
  final String host;
  final int port;
  final NetworkProxyType type;

  const NetworkProxyEndpoint({
    required this.host,
    required this.port,
    required this.type,
  });

  String get findProxyRule {
    final rule = type == NetworkProxyType.socks ? 'SOCKS' : 'PROXY';
    return '$rule $host:$port; DIRECT';
  }

  String get label {
    final typeLabel = type == NetworkProxyType.socks ? 'SOCKS5' : 'HTTP';
    return '$typeLabel $host:$port';
  }
}

class NetworkProxy {
  static final _user = UserManager();
  static bool _initialized = false;
  static NetworkProxyEndpoint? _systemProxy;

  static NetworkProxyEndpoint? get systemProxy => _systemProxy;

  static String get systemProxyDescription => _systemProxy?.label ?? '未检测到系统代理';

  static String get activeProxyDescription {
    switch (_user.networkProxyMode) {
      case NetworkProxyMode.system:
        return _systemProxy?.label ?? '系统代理：未检测到';
      case NetworkProxyMode.manual:
        return _manualProxy?.label ?? '手动代理：未配置';
      case NetworkProxyMode.direct:
        return '直连';
    }
  }

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    HttpOverrides.global = _ProxyHttpOverrides();
    await refreshSystemProxy();
    _registerNativeProxyCallback();
  }

  static Future<NetworkProxyEndpoint?> refreshSystemProxy() async {
    final proxy =
        await _readNativeSystemProxy() ??
        await _readWindowsSystemProxy() ??
        _readEnvironmentProxy(Uri.parse('https://www.google.com/'));
    _systemProxy = proxy;
    return proxy;
  }

  static HttpClient createHttpClient({
    Duration? connectionTimeout,
    bool useProxy = true,
  }) {
    final client = HttpClient();
    client.findProxy = useProxy ? findProxy : directFindProxy;
    if (connectionTimeout != null) {
      client.connectionTimeout = connectionTimeout;
    }
    return client;
  }

  static String directFindProxy(Uri uri) => 'DIRECT';

  static String findProxy(Uri uri) {
    if (_isLocalUri(uri) || _isUpdateMirrorUri(uri)) return 'DIRECT';

    switch (_user.networkProxyMode) {
      case NetworkProxyMode.system:
        return _systemProxy?.findProxyRule ??
            _readEnvironmentProxy(uri)?.findProxyRule ??
            'DIRECT';
      case NetworkProxyMode.manual:
        return _manualProxy?.findProxyRule ?? 'DIRECT';
      case NetworkProxyMode.direct:
        return 'DIRECT';
    }
  }

  static NetworkProxyEndpoint? parseManualProxy({
    required String host,
    required String port,
    required NetworkProxyType type,
  }) {
    final trimmedHost = host.trim();
    final parsedPort = int.tryParse(port.trim());
    if (trimmedHost.isEmpty) return null;

    return _parseHostPort(trimmedHost, type, fallbackPort: parsedPort);
  }

  static NetworkProxyEndpoint? get _manualProxy {
    if (!_user.hasManualProxy) return null;
    return NetworkProxyEndpoint(
      host: _user.networkProxyHost,
      port: _user.networkProxyPort,
      type: _user.networkProxyType,
    );
  }

  static Future<NetworkProxyEndpoint?> _readNativeSystemProxy() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    try {
      final setting = await NativeProxyReader.proxySetting.timeout(
        const Duration(seconds: 2),
      );
      final host = setting.host?.trim();
      final port = setting.port;
      if (setting.enabled &&
          host != null &&
          host.isNotEmpty &&
          UserManager.isValidProxyPort(port)) {
        return NetworkProxyEndpoint(
          host: host,
          port: port!,
          type: NetworkProxyType.http,
        );
      }
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }

    return null;
  }

  static Future<NetworkProxyEndpoint?> _readWindowsSystemProxy() async {
    if (!Platform.isWindows) return null;

    const registryPath =
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    try {
      final enableResult = await Process.run('reg', [
        'query',
        registryPath,
        '/v',
        'ProxyEnable',
      ]).timeout(const Duration(seconds: 2));
      if (enableResult.exitCode != 0 ||
          !_windowsProxyEnabled(enableResult.stdout.toString())) {
        return null;
      }

      final serverResult = await Process.run('reg', [
        'query',
        registryPath,
        '/v',
        'ProxyServer',
      ]).timeout(const Duration(seconds: 2));
      if (serverResult.exitCode != 0) return null;

      return _parseWindowsProxyServer(serverResult.stdout.toString());
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static NetworkProxyEndpoint? _readEnvironmentProxy(Uri uri) {
    try {
      return _parseFindProxyResult(HttpClient.findProxyFromEnvironment(uri));
    } catch (_) {
      return null;
    }
  }

  static void _registerNativeProxyCallback() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      NativeProxyReader.setProxyChangedCallback((setting) async {
        final host = setting.host?.trim();
        final port = setting.port;
        if (setting.enabled &&
            host != null &&
            host.isNotEmpty &&
            UserManager.isValidProxyPort(port)) {
          _systemProxy = NetworkProxyEndpoint(
            host: host,
            port: port!,
            type: NetworkProxyType.http,
          );
        } else {
          _systemProxy = null;
        }
      });
    } catch (_) {}
  }

  static bool _windowsProxyEnabled(String output) {
    final normalized = output.toLowerCase();
    return normalized.contains('proxyenable') &&
        (normalized.contains('0x1') || RegExp(r'\b1\b').hasMatch(normalized));
  }

  static NetworkProxyEndpoint? _parseWindowsProxyServer(String output) {
    final lines = output.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final index = line.toLowerCase().indexOf('proxyserver');
      if (index < 0) continue;

      final value = line.substring(index + 'proxyserver'.length).trim();
      final parts = value.split(RegExp(r'\s+'));
      final server = parts.isEmpty ? '' : parts.last.trim();
      if (server.isEmpty || server.toLowerCase().startsWith('reg_')) {
        continue;
      }

      return _parseWindowsProxyValue(server);
    }
    return null;
  }

  static NetworkProxyEndpoint? _parseWindowsProxyValue(String value) {
    if (!value.contains('=')) {
      return _parseHostPort(value, NetworkProxyType.http);
    }

    final entries = <String, String>{};
    for (final segment in value.split(';')) {
      final index = segment.indexOf('=');
      if (index <= 0) continue;
      entries[segment.substring(0, index).trim().toLowerCase()] = segment
          .substring(index + 1)
          .trim();
    }

    final socks = entries['socks'];
    final candidate = entries['https'] ?? entries['http'] ?? socks;
    final type = candidate == socks
        ? NetworkProxyType.socks
        : NetworkProxyType.http;
    return candidate == null ? null : _parseHostPort(candidate, type);
  }

  static NetworkProxyEndpoint? _parseFindProxyResult(String result) {
    for (final rawRule in result.split(';')) {
      final rule = rawRule.trim();
      if (rule.isEmpty || rule.toUpperCase() == 'DIRECT') continue;

      final upper = rule.toUpperCase();
      if (upper.startsWith('PROXY ')) {
        return _parseHostPort(
          rule.substring('PROXY '.length),
          NetworkProxyType.http,
        );
      }
      if (upper.startsWith('SOCKS ')) {
        return _parseHostPort(
          rule.substring('SOCKS '.length),
          NetworkProxyType.socks,
        );
      }
    }
    return null;
  }

  static NetworkProxyEndpoint? _parseHostPort(
    String value,
    NetworkProxyType type, {
    int? fallbackPort,
  }) {
    var text = value.trim();
    if (text.isEmpty) return null;

    final schemeIndex = text.indexOf('://');
    if (schemeIndex >= 0) {
      final uri = Uri.tryParse(text);
      final host = uri?.host.trim() ?? '';
      final port = uri?.hasPort == true ? uri!.port : fallbackPort;
      if (host.isNotEmpty && UserManager.isValidProxyPort(port)) {
        return NetworkProxyEndpoint(host: host, port: port!, type: type);
      }
      text = text.substring(schemeIndex + 3);
    }

    final atIndex = text.lastIndexOf('@');
    if (atIndex >= 0) text = text.substring(atIndex + 1);

    String host;
    int? port = fallbackPort;
    if (text.startsWith('[')) {
      final end = text.indexOf(']');
      if (end <= 0) return null;
      host = text.substring(1, end);
      if (end + 1 < text.length && text[end + 1] == ':') {
        port = int.tryParse(text.substring(end + 2));
      }
    } else {
      final colon = text.lastIndexOf(':');
      if (colon > 0) {
        host = text.substring(0, colon).trim();
        port = int.tryParse(text.substring(colon + 1).trim());
      } else {
        host = text.trim();
      }
    }

    if (host.isEmpty || !UserManager.isValidProxyPort(port)) return null;
    return NetworkProxyEndpoint(host: host, port: port!, type: type);
  }

  static bool _isLocalUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '::1' ||
        host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(host);
  }

  static bool _isUpdateMirrorUri(Uri uri) {
    final mirrorUri = Uri.tryParse(_user.updateMirrorPrefix);
    if (mirrorUri == null || !mirrorUri.hasScheme || !mirrorUri.hasAuthority) {
      return false;
    }

    return uri.scheme == mirrorUri.scheme &&
        uri.host.toLowerCase() == mirrorUri.host.toLowerCase() &&
        _effectivePort(uri) == _effectivePort(mirrorUri);
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme == 'http' ? 80 : 443;
  }
}

class _ProxyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..findProxy = NetworkProxy.findProxy;
  }
}
