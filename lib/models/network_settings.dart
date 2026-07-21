import 'package:shared_preferences/shared_preferences.dart';

import 'network_proxy_types.dart';
import 'prefs_store.dart';

/// 网络节点选择模式。
/// - [route]: 线路模式，在选定线路的多个 host 间随机/加权轮询。
/// - [fixedNode]: 固定节点模式，始终使用用户指定的某颗节点。
///
/// 历史版本曾存在 [automatic]「自动选择」模式，依据节点延迟历史自动选优；
/// 该模式及相关的历史记录、熔断、通畅锁定机制均已移除。若用户之前保存的
/// 选择模式索引对应旧的 automatic 值，初始化与加载时会一并回落到 [route]。
enum NetworkSelectionMode { route, fixedNode }

/// Network configuration settings, extracted from UserManager.
class NetworkSettings extends PrefsStore {
  static final NetworkSettings _instance = NetworkSettings._();
  factory NetworkSettings() => _instance;
  NetworkSettings._();

  // ── Enums (kept here to avoid circular dependency with UserManager) ─

  // These are re-exported from user_manager.dart for backward compat.

  // ── Preference keys ────────────────────────────────────────────────

  static const _keyApiRoute = 'api_route';
  static const _keySelectionMode = 'network_selection_mode';
  static const _keyFixedNodeHost = 'network_fixed_node_host';
  static const _keyProxyMode = 'network_proxy_mode';
  static const _keyProxyType = 'network_proxy_type';
  static const _keyProxyHost = 'network_proxy_host';
  static const _keyProxyPort = 'network_proxy_port';

  // ── Fields ─────────────────────────────────────────────────────────

  int _apiRoute = 0;
  NetworkSelectionMode _selectionMode = NetworkSelectionMode.route;
  String? _fixedNodeHost;
  NetworkProxyMode _proxyMode = NetworkProxyMode.system;
  NetworkProxyType _proxyType = NetworkProxyType.http;
  String _proxyHost = '';
  int _proxyPort = 0;

  // ── Getters ────────────────────────────────────────────────────────

  int get apiRoute => _apiRoute;
  NetworkSelectionMode get selectionMode => _selectionMode;
  String? get fixedNodeHost => _fixedNodeHost;
  NetworkProxyMode get proxyMode => _proxyMode;
  NetworkProxyType get proxyType => _proxyType;
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;
  bool get hasManualProxy => _proxyHost.isNotEmpty && _proxyPort > 0;

  // ── Init ───────────────────────────────────────────────────────────

  Future<void> initFromPrefs(SharedPreferences prefs) async {
    // 锁定后续 setter 使用的 prefs 与本次 init 读取的为同一实例,
    // 避免在测试 mock 切换场景下 setter 写到与 init 读到不同步的另一份 prefs。
    syncPrefs(prefs);
    _apiRoute = prefs.getInt(_keyApiRoute) ?? 0;
    _selectionMode = _normalizeSelectionMode(prefs.getInt(_keySelectionMode));
    // 若旧版本持久化的是已删除的 automatic(索引 2),自动回落为 route,并修正持久化。
    if (_selectionMode == NetworkSelectionMode.route &&
        prefs.getInt(_keySelectionMode) == 2) {
      await prefs.setInt(_keySelectionMode, _selectionMode.index);
    }
    _fixedNodeHost = prefs.getString(_keyFixedNodeHost)?.trim();
    _proxyMode = _normalizeProxyMode(prefs.getInt(_keyProxyMode));
    _proxyType = _normalizeProxyType(prefs.getInt(_keyProxyType));
    _proxyHost = prefs.getString(_keyProxyHost)?.trim() ?? '';
    _proxyPort = _normalizePort(prefs.getInt(_keyProxyPort));
  }

  // ── Setters ────────────────────────────────────────────────────────

  Future<void> setApiRoute(int route) async {
    _apiRoute = route;
    await setInt(_keyApiRoute, route);
  }

  Future<void> setSelectionMode(NetworkSelectionMode mode) async {
    if (_selectionMode == mode) return;
    _selectionMode = mode;
    await setInt(_keySelectionMode, mode.index);
    notifyListeners();
  }

  Future<void> setFixedNodeHost(String? host) async {
    final next = host?.trim();
    _fixedNodeHost = next == null || next.isEmpty ? null : next;
    final p = await prefs;
    if (_fixedNodeHost == null) {
      await p.remove(_keyFixedNodeHost);
    } else {
      await p.setString(_keyFixedNodeHost, _fixedNodeHost!);
    }
    notifyListeners();
  }

  Future<void> setProxyMode(NetworkProxyMode mode) async {
    if (_proxyMode == mode) return;
    _proxyMode = mode;
    await setInt(_keyProxyMode, mode.index);
  }

  Future<void> setManualProxy({
    required String host,
    required int port,
    required NetworkProxyType type,
    bool enable = true,
  }) async {
    final nextHost = host.trim();
    final nextPort = _normalizePort(port);
    if (nextHost.isEmpty || nextPort == 0) return;

    final shouldNotify =
        _proxyHost != nextHost ||
        _proxyPort != nextPort ||
        _proxyType != type ||
        (enable && _proxyMode != NetworkProxyMode.manual);

    _proxyHost = nextHost;
    _proxyPort = nextPort;
    _proxyType = type;
    if (enable) {
      _proxyMode = NetworkProxyMode.manual;
    }

    final p = await prefs;
    await p.setString(_keyProxyHost, nextHost);
    await p.setInt(_keyProxyPort, nextPort);
    await p.setInt(_keyProxyType, type.index);
    if (enable) {
      await p.setInt(_keyProxyMode, NetworkProxyMode.manual.index);
    }

    if (shouldNotify) notifyListeners();
  }

  // ── Normalizers ────────────────────────────────────────────────────

  static bool isValidProxyPort(int? port) =>
      port != null && port > 0 && port <= 65535;

  static NetworkProxyMode _normalizeProxyMode(int? index) {
    if (index == null || index < 0 || index >= NetworkProxyMode.values.length) {
      return NetworkProxyMode.system;
    }
    return NetworkProxyMode.values[index];
  }

  static NetworkProxyType _normalizeProxyType(int? index) {
    if (index == null || index < 0 || index >= NetworkProxyType.values.length) {
      return NetworkProxyType.http;
    }
    return NetworkProxyType.values[index];
  }

  static NetworkSelectionMode _normalizeSelectionMode(int? index) {
    // 索引 0=route, 1=fixedNode;旧的索引 2(automatic)已删除,统一回落 route。
    if (index == null || index < 0 || index >= NetworkSelectionMode.values.length) {
      return NetworkSelectionMode.route;
    }
    return NetworkSelectionMode.values[index];
  }

  static int _normalizePort(int? port) => isValidProxyPort(port) ? port! : 0;
}
