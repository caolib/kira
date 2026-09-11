part of '../network_page.dart';

extension _NetworkActions on _NetworkPageState {
  int _nodeNumber(int routeIndex, int localIndex) =>
      routes.take(routeIndex).fold(0, (sum, route) => sum + route.length) +
      localIndex +
      1;

  String? _bestLatencyHost(Map<int, Map<String, int?>> results) {
    String? bestHost;
    int? bestLatency;
    for (var route = 0; route < ApiClient.routeCount; route++) {
      final entries = results[route]?.entries;
      if (entries == null) continue;
      for (final entry in entries) {
        final latency = entry.value;
        if (latency != null && (bestLatency == null || latency < bestLatency)) {
          bestHost = entry.key;
          bestLatency = latency;
        }
      }
    }
    return bestHost;
  }

  Color _latencyTone(double avg, ColorScheme cs) {
    if (avg <= 800) return Colors.green;
    if (avg <= 2000) return Colors.orange;
    return cs.error;
  }

  String _latencyHostKey(int index, String host) => '$index|$host';

  bool _isLatencyPending(int index, String host) {
    return _pendingLatencyHosts.contains(_latencyHostKey(index, host));
  }

  // ─────────────────────────────────────────────────────────────────────
  // 操作逻辑
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _setSelectionMode(NetworkSelectionMode mode) async {
    if (mode == NetworkSelectionMode.fixedNode && _user.fixedNodeHost == null) {
      await _user.setFixedNodeHost(ApiClient().network.getRouteHosts(0).first);
    }
    await _user.setNetworkSelectionMode(mode);
  }

  Future<void> _testLatency() async {
    final api = ApiClient();
    final pendingResults = <int, Map<String, int?>>{};
    final pendingHosts = <String>{};
    for (var i = 0; i < ApiClient.routeCount; i++) {
      pendingResults[i] = {
        for (final host in api.network.getRouteHosts(i)) host: null,
      };
      pendingHosts.addAll(
        api.network.getRouteHosts(i).map((host) => _latencyHostKey(i, host)),
      );
    }
    pendingResults[-1] = {
      for (final host in api.network.getExtraApiHosts()) host: null,
    };
    pendingHosts.addAll(
      api.network.getExtraApiHosts().map((host) => _latencyHostKey(-1, host)),
    );

    void updateHostLatency(int index, String host, int? latency) {
      if (!mounted) return;
      _setState(() {
        _latencyResults[index]?[host] = latency;
        _pendingLatencyHosts.remove(_latencyHostKey(index, host));
      });
    }

    _setState(() {
      _testingLatency = true;
      _latencyResults = pendingResults;
      _pendingLatencyHosts = pendingHosts;
    });
    try {
      final tests = <Future<MapEntry<int, Map<String, int?>>>>[
        api.network
            .testExtraApiLatency(
              onHostResult: (host, latency) =>
                  updateHostLatency(-1, host, latency),
            )
            .then((r) => MapEntry(-1, r)),
      ];
      for (var route = 0; route < ApiClient.routeCount; route++) {
        tests.add(
          api.network
              .testRouteLatency(
                route,
                onHostResult: (host, latency) =>
                    updateHostLatency(route, host, latency),
              )
              .then((result) => MapEntry(route, result)),
        );
      }
      final results = await Future.wait(tests);
      final latencyResults = Map<int, Map<String, int?>>.fromEntries(results);
      // 仅 fixedNode 模式测速后自动选最低延迟节点;route 模式留给用户手动点选线路。
      if (_user.networkSelectionMode == NetworkSelectionMode.fixedNode) {
        final bestHost = _bestLatencyHost(latencyResults);
        if (bestHost != null && bestHost != _user.fixedNodeHost) {
          await _user.setFixedNodeHost(bestHost);
          if (mounted) {
            _showToast(
              AppLocalizations.of(context)!.networkFixedNodeAutoSelected,
            );
          }
        }
      }
      if (!mounted) return;
      _setState(() {
        _testingLatency = false;
        _latencyResults = latencyResults;
        _pendingLatencyHosts = {};
      });
    } catch (_) {
      if (!mounted) return;
      _setState(() {
        _testingLatency = false;
        _pendingLatencyHosts = {};
      });
    }
  }

  Future<void> _refreshSystemProxy() async {
    _setState(() => _refreshingSystemProxy = true);
    final proxy = await NetworkProxy.refreshSystemProxy();
    if (!mounted) return;
    _setState(() => _refreshingSystemProxy = false);
    final l10n = AppLocalizations.of(context)!;
    _showToast(
      proxy == null
          ? l10n.networkNoSystemProxyDetected
          : l10n.networkSystemProxyDetected(proxy.label),
    );
  }

  Future<void> _setProxyMode(NetworkProxyMode mode) async {
    await _user.setNetworkProxyMode(mode);
    if (!mounted) return;
    _setState(() {});
  }

  Future<void> _setCopyLoginHost(String host) async {
    if (host == _user.copyLoginHost) return;
    await _user.setCopyLoginHost(host);
    if (!mounted) return;
    // 延迟结果按 host 记录，切换后清空以反映新的测试目标。
    _setState(() {
      _latencyResults = {};
      _pendingLatencyHosts = {};
    });
  }

  Future<void> _saveCopyAdvancedSettings() async {
    final host = UserManager.normalizeCopyApiHost(_copyApiHostController.text);
    final version = UserManager.normalizeCopyAppVersion(
      _copyAppVersionController.text,
    );
    final hostChanged = host != _user.copyApiHost;

    _copyApiHostController.text = host;
    _copyAppVersionController.text = version;

    await _user.setCopyApiHost(host);
    await _user.setCopyAppVersion(version);
    if (!mounted) return;

    if (hostChanged) {
      _setState(() {
        _latencyResults = {};
        _pendingLatencyHosts = {};
      });
    }
    _showToast(AppLocalizations.of(context)!.networkCopyAdvancedSaved);
  }

  Future<void> _resetCopyAdvancedSettings() async {
    final hostChanged = _user.copyApiHost != defaultCopyApiHost;
    _copyApiHostController.text = defaultCopyApiHost;
    _copyAppVersionController.text = defaultCopyAppVersion;

    await _user.setCopyApiHost(defaultCopyApiHost);
    await _user.setCopyAppVersion(defaultCopyAppVersion);
    if (!mounted) return;

    if (hostChanged) {
      _setState(() {
        _latencyResults = {};
        _pendingLatencyHosts = {};
      });
    }
    _showToast(AppLocalizations.of(context)!.networkCopyAdvancedReset);
  }

  Future<void> _autoFillCopySettings() async {
    if (_autoFillingCopySettings) return;

    _setState(() => _autoFillingCopySettings = true);

    try {
      final apiHost = await ApiClient().network.fetchCopyApiHost();
      final version = await ApiClient().manga.fetchCopyLatestAppVersion();
      if (!mounted) return;
      _copyApiHostController.text = apiHost;
      _copyAppVersionController.text = version;
      _showToast(
        AppLocalizations.of(context)!.networkCopyAutoFilled(apiHost, version),
      );
    } catch (e) {
      if (!mounted) return;
      _showToast(
        AppLocalizations.of(context)!.networkAutoFillFailed(_errorMessage(e)),
        isError: true,
      );
    } finally {
      if (mounted) {
        _setState(() => _autoFillingCopySettings = false);
      }
    }
  }

  String _errorMessage(Object error) {
    if (error is DioException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;

      final statusCode = error.response?.statusCode;
      if (statusCode != null) return 'HTTP $statusCode';

      final rawError = error.error?.toString();
      if (rawError != null && rawError.isNotEmpty) return rawError;
    }
    return error.toString();
  }

  Future<void> _saveManualProxy() async {
    final proxy = NetworkProxy.parseManualProxy(
      host: _proxyAddressController.text,
      port: '',
      type: _manualProxyType,
    );
    if (proxy == null) {
      _showToast(
        AppLocalizations.of(context)!.networkInvalidProxyAddress,
        isError: true,
      );
      return;
    }

    _proxyAddressController.text = proxy.host.contains(':')
        ? '[${proxy.host}]:${proxy.port}'
        : '${proxy.host}:${proxy.port}';
    _manualProxyType = proxy.type;

    await _user.setManualProxy(
      host: proxy.host,
      port: proxy.port,
      type: proxy.type,
    );
    if (!mounted) return;
    _setState(() {});
    _showToast(AppLocalizations.of(context)!.networkProxyEnabled(proxy.label));
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    showToast(context, message, isError: isError);
  }
}
