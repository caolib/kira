import 'dart:async';

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
  static const _keyAutoTestEnabled = 'network_auto_test_enabled';
  static const _keyAutoTestIntervalHours = 'network_auto_test_interval_hours';
  static const _keyLastAutoTestAt = 'network_last_auto_test_at';

  static const autoTestIntervalOptions = [1, 3, 6, 24];
  static const _keyProxyMode = 'network_proxy_mode';
  static const _keyProxyType = 'network_proxy_type';
  static const _keyProxyHost = 'network_proxy_host';
  static const _keyProxyPort = 'network_proxy_port';

  // ── Fields ─────────────────────────────────────────────────────────

  int _apiRoute = 0;
  NetworkSelectionMode _selectionMode = NetworkSelectionMode.route;
  String? _fixedNodeHost;
  bool _autoTestEnabled = false;
  int _autoTestIntervalHours = 1;
  DateTime? _lastAutoTestAt;
  NetworkProxyMode _proxyMode = NetworkProxyMode.system;
  NetworkProxyType _proxyType = NetworkProxyType.http;
  String _proxyHost = '';
  int _proxyPort = 0;
  int _selectionRevision = 0;
  int _autoTestRevision = 0;
  Future<void>? _pendingAutoTestWrite;

  // ── Getters ────────────────────────────────────────────────────────

  int get apiRoute => _apiRoute;
  NetworkSelectionMode get selectionMode => _selectionMode;
  String? get fixedNodeHost => _fixedNodeHost;
  bool get autoTestEnabled => _autoTestEnabled;
  int get autoTestIntervalHours => _autoTestIntervalHours;
  Duration get autoTestInterval => Duration(hours: _autoTestIntervalHours);
  DateTime? get lastAutoTestAt => _lastAutoTestAt;
  int get selectionRevision => _selectionRevision;
  int get autoTestRevision => _autoTestRevision;
  NetworkProxyMode get proxyMode => _proxyMode;
  NetworkProxyType get proxyType => _proxyType;
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;
  bool get hasManualProxy => _proxyHost.isNotEmpty && _proxyPort > 0;

  // ── Init ───────────────────────────────────────────────────────────

  Future<void> initFromPrefs(
    SharedPreferences prefs, {
    bool persistMigrations = true,
  }) async {
    // 锁定后续 setter 使用的 prefs 与本次 init 读取的为同一实例,
    // 避免在测试 mock 切换场景下 setter 写到与 init 读到不同步的另一份 prefs。
    await _pendingAutoTestWrite;
    syncPrefs(prefs);
    _selectionRevision++;
    _autoTestRevision++;
    _apiRoute = prefs.getInt(_keyApiRoute) ?? 0;
    _selectionMode = _normalizeSelectionMode(prefs.getInt(_keySelectionMode));
    // 若旧版本持久化的是已删除的 automatic(索引 2),自动回落为 route,并修正持久化。
    if (persistMigrations &&
        _selectionMode == NetworkSelectionMode.route &&
        prefs.getInt(_keySelectionMode) == 2) {
      await prefs.setInt(_keySelectionMode, _selectionMode.index);
    }
    _fixedNodeHost = prefs.getString(_keyFixedNodeHost)?.trim();
    _autoTestEnabled = prefs.getBool(_keyAutoTestEnabled) ?? false;
    _autoTestIntervalHours = _normalizeAutoTestInterval(
      prefs.getInt(_keyAutoTestIntervalHours),
    );
    final lastTest = prefs.getInt(_keyLastAutoTestAt);
    _lastAutoTestAt = lastTest == null || lastTest <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastTest);
    _proxyMode = _normalizeProxyMode(prefs.getInt(_keyProxyMode));
    _proxyType = _normalizeProxyType(prefs.getInt(_keyProxyType));
    _proxyHost = prefs.getString(_keyProxyHost)?.trim() ?? '';
    _proxyPort = _normalizePort(prefs.getInt(_keyProxyPort));
  }

  // ── Setters ────────────────────────────────────────────────────────

  Future<void> setApiRoute(int route) async {
    _selectionRevision++;
    _apiRoute = route;
    await setInt(_keyApiRoute, route);
  }

  Future<void> setSelectionMode(NetworkSelectionMode mode) async {
    if (_selectionMode == mode) return;
    _selectionRevision++;
    _selectionMode = mode;
    await setInt(_keySelectionMode, mode.index);
    notifyListeners();
  }

  Future<void> setFixedNodeHost(String? host) async {
    _selectionRevision++;
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

  Future<void> setAutoTestEnabled(bool enabled) async {
    if (_autoTestEnabled == enabled) return;
    _autoTestEnabled = enabled;
    _autoTestRevision++;
    // 重新开启从此刻开始计时，不沿用关闭前的排期。
    final time = enabled ? DateTime.now() : null;
    if (time != null) _lastAutoTestAt = time;
    final write = _queueAutoTestWrite(() async {
      if (time != null) {
        await setInt(
          _keyLastAutoTestAt,
          time.millisecondsSinceEpoch,
          notify: false,
        );
      }
      await setBool(_keyAutoTestEnabled, enabled, notify: false);
    });
    notifyListeners();
    await write;
  }

  Future<void> setAutoTestIntervalHours(int hours) async {
    final next = _normalizeAutoTestInterval(hours);
    if (_autoTestIntervalHours == next) return;
    _autoTestIntervalHours = next;
    _autoTestRevision++;
    final write = _queueAutoTestWrite(
      () => setInt(_keyAutoTestIntervalHours, next, notify: false),
    );
    notifyListeners();
    await write;
  }

  Future<void> markAutoTest(DateTime time) {
    _lastAutoTestAt = time;
    return _queueAutoTestWrite(
      () => setInt(
        _keyLastAutoTestAt,
        time.millisecondsSinceEpoch,
        notify: false,
      ),
    );
  }

  // 开关、间隔和时间戳按调用顺序落盘，快速操作不会让旧写入覆盖新状态。
  Future<void> _queueAutoTestWrite(Future<void> Function() action) {
    final previous = _pendingAutoTestWrite;
    final barrier = Completer<void>();
    _pendingAutoTestWrite = barrier.future;
    Future<void> run() async {
      try {
        await action();
      } finally {
        if (identical(_pendingAutoTestWrite, barrier.future)) {
          _pendingAutoTestWrite = null;
        }
        barrier.complete();
      }
    }

    return previous == null ? run() : previous.then((_) => run());
  }

  Future<void> flushAutoTestWrites() async => await _pendingAutoTestWrite;

  Future<void> setProxyMode(NetworkProxyMode mode) async {
    if (_proxyMode == mode) return;
    _selectionRevision++;
    _proxyMode = mode;
    await setInt(_keyProxyMode, mode.index);
    notifyListeners();
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

    if (shouldNotify) _selectionRevision++;
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
    if (index == null ||
        index < 0 ||
        index >= NetworkSelectionMode.values.length) {
      return NetworkSelectionMode.route;
    }
    return NetworkSelectionMode.values[index];
  }

  static int _normalizeAutoTestInterval(int? hours) =>
      autoTestIntervalOptions.contains(hours) ? hours! : 1;

  static int _normalizePort(int? port) => isValidProxyPort(port) ? port! : 0;
}
