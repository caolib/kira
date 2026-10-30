part of '../network_page.dart';

extension _NetworkActions on _NetworkPageState {
  int _nodeNumber(int routeIndex, int localIndex) =>
      routes.take(routeIndex).fold(0, (sum, route) => sum + route.length) +
      localIndex +
      1;

  Color _latencyTone(double avg, ColorScheme cs) {
    if (avg <= 800) return AppStatusColors.success(cs);
    if (avg <= 2000) return AppStatusColors.warning(cs);
    return AppStatusColors.danger(cs);
  }

  double? _averageLatency(Map<String, int?>? results) =>
      NetworkLatencyTester.averageLatency(results);

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
    if (_manualLatencyTest) return;
    _setState(() {
      _manualLatencyTest = true;
      _testingLatency = true;
      _latencyResults[-1] = {
        for (final host in _networkApi.getExtraApiHosts()) host: null,
      };
      _pendingLatencyHosts.addAll(
        _networkApi.getExtraApiHosts().map((host) => _latencyHostKey(-1, host)),
      );
    });
    try {
      await Future.wait([
        _latencyTester.testAndSelect(),
        _networkApi
            .testExtraApiLatency(
              onHostResult: (host, latency) {
                if (!mounted) return;
                _setState(() {
                  _latencyResults[-1]?[host] = latency;
                  _pendingLatencyHosts.remove(_latencyHostKey(-1, host));
                });
              },
            )
            .then((result) {
              if (mounted) _setState(() => _latencyResults[-1] = result);
            }),
      ]);
    } catch (error, stack) {
      unawaited(
        AppLogger.instance.recordWarning(
          error,
          stackTrace: stack,
          source: 'network.test',
        ),
      );
      if (!mounted) return;
      _showToast(
        AppLocalizations.of(
          context,
        )!.networkSpeedTestFailedDetail(NetworkError.message(error)),
        isError: true,
      );
    } finally {
      if (mounted) {
        _setState(() {
          _manualLatencyTest = false;
          _pendingLatencyHosts.removeWhere((key) => key.startsWith('-1|'));
          _syncLatencyResults();
        });
      }
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

  // 切换/删除/修改登录域名后，延迟结果里旧 host 的条目已失效，统一清空。
  void _resetLatencyResults() {
    _setState(() {
      _latencyResults = {};
      _pendingLatencyHosts = {};
    });
  }

  Future<void> _addCustomLoginHost() async {
    final value = _customLoginHostController.text.trim();
    final ok = await _user.addCustomCopyLoginHost(value);
    if (!mounted) return;
    if (!ok) {
      _showToast(
        AppLocalizations.of(context)!.networkCopyLoginDomainDuplicate,
        isError: true,
      );
      return;
    }
    _customLoginHostController.clear();
    unawaited(_testLoginHostLatency([value]));
  }

  Future<void> _removeCustomLoginHost(String host) async {
    final wasCurrent = _user.copyLoginHost == host;
    await _user.removeCustomCopyLoginHost(host);
    if (!mounted) return;
    _setState(() {
      _loginHostLatency.remove(host);
      _pendingLoginHosts.remove(host);
    });
    if (wasCurrent) _resetLatencyResults();
  }

  Future<void> _editCustomLoginHost(String host) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: host);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.networkCopyLoginDomainEditTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.commentSettingsSaveButton),
          ),
        ],
      ),
    );
    if (result == null) {
      controller.dispose();
      return;
    }
    controller.dispose();
    if (!mounted) return;

    final wasCurrent = _user.copyLoginHost == host;
    final ok = await _user.updateCustomCopyLoginHost(host, result);
    if (!mounted) return;
    if (!ok) {
      _showToast(
        AppLocalizations.of(context)!.networkCopyLoginDomainDuplicate,
        isError: true,
      );
      return;
    }
    _setState(() {
      _loginHostLatency.remove(host);
      _pendingLoginHosts.remove(host);
    });
    if (wasCurrent) _resetLatencyResults();
    unawaited(_testLoginHostLatency([result.trim()]));
  }

  /// 测试拷贝登录域名连通性（展开高级设置、新增/修改域名时触发）。
  /// [hosts] 缺省为当前全部可选域名。
  Future<void> _testLoginHostLatency([List<String>? hosts]) async {
    final targets = hosts ?? _user.copyLoginHostChoices;
    if (targets.isEmpty) return;

    _setState(() => _pendingLoginHosts.addAll(targets));
    await _networkApi.testHostsConnectivity(
      targets,
      onHostResult: (host, latency) {
        if (!mounted) return;
        _setState(() {
          _loginHostLatency[host] = latency;
          _pendingLoginHosts.remove(host);
        });
      },
    );
    if (!mounted) return;
    _setState(() => _pendingLoginHosts.removeAll(targets));
  }

  Future<void> _saveCopyAdvancedSettings() async {
    final host = UserManager.normalizeCopyApiHost(_copyApiHostController.text);
    final version = UserManager.normalizeCopyAppVersion(
      _copyAppVersionController.text,
    );
    final versionCode = UserManager.normalizeCopyVersionCode(
      _copyVersionCodeController.text,
    );
    final hostChanged = host != _user.copyApiHost;

    _copyApiHostController.text = host;
    _copyAppVersionController.text = version;
    _copyVersionCodeController.text = versionCode;

    await _user.setCopyApiHost(host);
    await _user.setCopyAppVersion(version);
    await _user.setCopyVersionCode(versionCode);
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
    _copyVersionCodeController.text = defaultCopyVersionCode;

    await _user.setCopyApiHost(defaultCopyApiHost);
    await _user.setCopyAppVersion(defaultCopyAppVersion);
    await _user.setCopyVersionCode(defaultCopyVersionCode);
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
