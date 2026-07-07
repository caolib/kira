import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../api/api_transport.dart';
import '../l10n/app_localizations.dart';
import '../models/user_manager.dart';
import '../utils/network_proxy.dart';
import '../utils/toast.dart';

class NetworkPage extends StatefulWidget {
  const NetworkPage({super.key});

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  static const _googleConnectivityTimeout = Duration(seconds: 3);

  final _user = UserManager();
  final _proxyAddressController = TextEditingController();
  final _copyApiHostController = TextEditingController();
  final _copyAppVersionController = TextEditingController();
  bool _testingLatency = false;
  bool _testingGoogleConnectivity = false;
  bool _refreshingSystemProxy = false;
  bool _latencyExpanded = true;
  bool _advancedSettingsExpanded = false;
  bool _autoFillingCopySettings = false;
  NetworkProxyType _manualProxyType = NetworkProxyType.http;
  Map<int, Map<String, int?>> _latencyResults = {};
  Set<String> _pendingLatencyHosts = {};
  bool? _googleConnectivityOk;
  int? _googleConnectivityLatencyMs;
  String? _googleConnectivityMessage;

  @override
  void initState() {
    super.initState();
    _proxyAddressController.text = _manualProxyAddress;
    _copyApiHostController.text = _user.copyApiHost;
    _copyAppVersionController.text = _user.copyAppVersion;
    _manualProxyType = _user.networkProxyType;
    _user.addListener(_onChanged);
  }

  @override
  void dispose() {
    _user.removeListener(_onChanged);
    _proxyAddressController.dispose();
    _copyApiHostController.dispose();
    _copyAppVersionController.dispose();
    super.dispose();
  }

  String get _manualProxyAddress {
    if (!_user.hasManualProxy) return '';

    final host = _user.networkProxyHost;
    final needsBrackets =
        host.contains(':') && !host.startsWith('[') && !host.endsWith(']');
    final displayHost = needsBrackets ? '[$host]' : host;
    return '$displayHost:${_user.networkProxyPort}';
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final avgLatency = _averageLatency(_latencyResults[_user.apiRoute]);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.networkTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: cs.outlineVariant),
            ),
            color: cs.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.dns_outlined, color: cs.primary),
                          const SizedBox(width: 12),
                          Text(
                            l10n.networkApiRouteTitle,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          segments: [
                            ButtonSegment(
                              value: 0,
                              label: Text(l10n.networkRouteLabel(1)),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text(l10n.networkRouteLabel(2)),
                            ),
                          ],
                          selected: {_user.apiRoute},
                          onSelectionChanged: (v) => _user.setApiRoute(v.first),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _testingLatency ? null : _testLatency,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.speed, color: cs.onSurfaceVariant),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.networkTestLatency,
                                  style: tt.bodyLarge,
                                ),
                                if (_testingLatency) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: cs.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.networkTestingNodes,
                                        style: tt.bodySmall,
                                      ),
                                    ],
                                  ),
                                ] else if (_latencyResults.isEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.networkNotTested,
                                    style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!_testingLatency) _buildLatencyTrailingIcon(cs),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_latencyResults.isNotEmpty && _latencyExpanded) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildLatencyDetail(tt, cs),
                  ),
                ],
              ],
            ),
          ),
          _buildProxyCard(tt, cs),
          _buildGoogleConnectivityCard(tt, cs),
          if (avgLatency != null && avgLatency > 1500)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Material(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: cs.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.networkHighLatencyProxySuggestion,
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          _buildAdvancedSettingsCard(tt, cs),
        ],
      ),
    );
  }

  String _latencyGroupLabel(int index) {
    final l10n = AppLocalizations.of(context)!;
    if (index >= 0 && index < ApiClient.routeCount) {
      return l10n.networkRouteLabel(index + 1);
    }
    return l10n.networkOtherRouteGroup;
  }

  double? _averageLatency(Map<String, int?>? results) {
    final values = results?.values.whereType<int>().toList() ?? const <int>[];
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  int? _bestLatencyRoute(Map<int, Map<String, int?>> results) {
    int? bestRoute;
    double? bestAverage;

    for (var i = 0; i < ApiClient.routeCount; i++) {
      final average = _averageLatency(results[i]);
      if (average == null) continue;
      if (bestAverage == null || average < bestAverage) {
        bestAverage = average;
        bestRoute = i;
      }
    }

    return bestRoute;
  }

  String _latencyHostKey(int index, String host) => '$index|$host';

  bool _isLatencyPending(int index, String host) {
    return _pendingLatencyHosts.contains(_latencyHostKey(index, host));
  }

  Widget _buildLatencyTrailingIcon(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    if (_latencyResults.isEmpty) {
      return Icon(Icons.chevron_right, color: cs.onSurfaceVariant);
    }

    return IconButton(
      tooltip: _latencyExpanded
          ? l10n.networkCollapseTestResults
          : l10n.networkExpandTestResults,
      onPressed: () {
        setState(() => _latencyExpanded = !_latencyExpanded);
      },
      icon: Icon(
        _latencyExpanded
            ? Icons.keyboard_arrow_up_rounded
            : Icons.keyboard_arrow_down_rounded,
        color: cs.primary,
      ),
    );
  }

  Widget _buildProxyCard(TextTheme tt, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final isManualMode = _user.networkProxyMode == NetworkProxyMode.manual;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant),
        ),
        color: cs.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.settings_ethernet, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.networkProxySettings,
                      style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.networkRefreshSystemProxy,
                    onPressed: _refreshingSystemProxy
                        ? null
                        : _refreshSystemProxy,
                    icon: _refreshingSystemProxy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary,
                            ),
                          )
                        : const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<NetworkProxyMode>(
                  segments: [
                    ButtonSegment(
                      value: NetworkProxyMode.system,
                      label: Text(l10n.networkProxySystem),
                    ),
                    ButtonSegment(
                      value: NetworkProxyMode.manual,
                      label: Text(l10n.networkProxyManual),
                    ),
                  ],
                  selected: {_user.networkProxyMode},
                  onSelectionChanged: (value) => _setProxyMode(value.first),
                ),
              ),
              const SizedBox(height: 12),
              _buildProxyStatusRow(
                icon: Icons.route_outlined,
                label: l10n.networkCurrentProxy,
                value: NetworkProxy.activeProxyDescription(l10n),
                tt: tt,
                cs: cs,
              ),
              if (isManualMode) ...[
                const SizedBox(height: 16),
                SegmentedButton<NetworkProxyType>(
                  segments: const [
                    ButtonSegment(
                      value: NetworkProxyType.http,
                      label: Text('HTTP'),
                    ),
                    ButtonSegment(
                      value: NetworkProxyType.socks,
                      label: Text('SOCKS5'),
                    ),
                  ],
                  selected: {_manualProxyType},
                  onSelectionChanged: (value) {
                    setState(() => _manualProxyType = value.first);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _proxyAddressController,
                  decoration: InputDecoration(
                    labelText: l10n.networkProxyAddress,
                    hintText: l10n.networkProxyAddressHint,
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _saveManualProxy(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saveManualProxy,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(l10n.networkSaveAndEnableManualProxy),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool get _hasActiveProxy {
    if (_user.networkProxyMode == NetworkProxyMode.manual) {
      return _user.hasManualProxy;
    }
    return NetworkProxy.systemProxy != null;
  }

  Widget _buildProxyStatusRow({
    required IconData icon,
    required String label,
    required String value,
    required TextTheme tt,
    required ColorScheme cs,
  }) {
    final hasProxy = _hasActiveProxy;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Text('$label: ', style: tt.bodySmall),
        const Spacer(),
        if (hasProxy)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.green.shade800,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.bodySmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _buildGoogleConnectivityCard(TextTheme tt, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    final hasResult = _googleConnectivityMessage != null;
    final ok = _googleConnectivityOk == true;
    final statusColor = _testingGoogleConnectivity
        ? cs.primary
        : hasResult
        ? (ok ? Colors.green : cs.error)
        : cs.onSurfaceVariant;
    final subtitle = _testingGoogleConnectivity
        ? l10n.networkTestingGoogle(NetworkProxy.activeProxyDescription(l10n))
        : _googleConnectivityMessage;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant),
        ),
        color: cs.surfaceContainerLow,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _testingGoogleConnectivity ? null : _testGoogleConnectivity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  _testingGoogleConnectivity
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: cs.primary,
                          ),
                        )
                      : Icon(
                          ok ? Icons.check_circle_outline : Icons.public,
                          color: statusColor,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.networkGoogleConnectivity,
                      style: tt.bodyLarge,
                    ),
                  ),
                  if (subtitle != null)
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: hasResult || _testingGoogleConnectivity
                              ? statusColor
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (_googleConnectivityLatencyMs != null &&
                      !_testingGoogleConnectivity)
                    Container(
                      margin: const EdgeInsets.only(left: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_googleConnectivityLatencyMs ms',
                        style: tt.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else if (!_testingGoogleConnectivity)
                    Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedSettingsCard(TextTheme tt, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant),
        ),
        color: cs.surfaceContainerLow,
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(
                    () =>
                        _advancedSettingsExpanded = !_advancedSettingsExpanded,
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tune, color: cs.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.networkAdvancedSettings,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        _advancedSettingsExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_advancedSettingsExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _copyApiHostController,
                      decoration: const InputDecoration(
                        labelText: 'COPY API URL',
                        hintText: defaultCopyApiHost,
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _copyAppVersionController,
                      decoration: InputDecoration(
                        labelText: l10n.networkCopyAppVersion,
                        hintText: defaultCopyAppVersion,
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saveCopyAdvancedSettings(),
                    ),
                    const SizedBox(height: 12),
                    _buildAdvancedSettingsActions(cs),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSettingsActions(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: double.infinity,
      child: _ConnectedButtonGroup(
        children: [
          _ConnectedButtonGroupItem(
            onPressed: _autoFillingCopySettings ? null : _autoFillCopySettings,
            loadingWidget: _autoFillingCopySettings
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : null,
            icon: _autoFillingCopySettings ? null : Icons.auto_fix_high,
            label: l10n.networkFill,
          ),
          _ConnectedButtonGroupItem(
            onPressed: _autoFillingCopySettings
                ? null
                : _resetCopyAdvancedSettings,
            icon: Icons.restart_alt,
            label: l10n.commentSettingsResetButton,
          ),
          _ConnectedButtonGroupItem(
            onPressed: _saveCopyAdvancedSettings,
            icon: Icons.save_outlined,
            label: l10n.commentSettingsSaveButton,
            isPrimary: true,
          ),
        ],
      ),
    );
  }

  Widget _buildLatencyDetail(TextTheme tt, ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    if (_latencyResults.isEmpty) return const SizedBox.shrink();

    return Column(
      children: _latencyResults.entries.map((entry) {
        final index = entry.key;
        final hosts = entry.value;
        final hostEntries = hosts.entries.toList();
        final average = index < 0 ? null : _averageLatency(hosts);
        final hasPending = hostEntries.any(
          (entry) => _isLatencyPending(index, entry.key),
        );
        final averageLabel = average == null
            ? (hasPending
                  ? l10n.networkAverageTesting
                  : l10n.networkAverageTimeout)
            : l10n.networkAverageLatency(average.round());
        final averageColor = average == null
            ? (hasPending ? cs.onSurfaceVariant : cs.error)
            : average <= 800
            ? Colors.green
            : average <= 2000
            ? Colors.orange
            : cs.error;

        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _latencyGroupLabel(index),
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.82),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0,
                    ),
                  ),
                  if (index >= 0) ...[
                    const Spacer(),
                    Text(
                      averageLabel,
                      style: tt.labelMedium?.copyWith(
                        color: averageColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 8.0;
                  final itemWidth = (constraints.maxWidth - spacing * 2) / 3;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: List.generate(hostEntries.length, (i) {
                      final title = index < 0
                          ? ApiClient().network.getExtraApiHostLabel(
                              hostEntries[i].key,
                              l10n,
                            )
                          : l10n.networkNodeLabel(i + 1);
                      final latency = hostEntries[i].value;
                      final isPending = _isLatencyPending(
                        index,
                        hostEntries[i].key,
                      );

                      Color statusColor;
                      if (isPending) {
                        statusColor = cs.onSurfaceVariant;
                      } else if (latency == null) {
                        statusColor = cs.error;
                      } else if (latency <= 800) {
                        statusColor = Colors.green;
                      } else if (latency <= 2000) {
                        statusColor = Colors.orange;
                      } else {
                        statusColor = cs.error;
                      }

                      return SizedBox(
                        width: itemWidth,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withValues(
                              alpha: 0.4,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: statusColor.withValues(
                                alpha: latency != null
                                    ? 0.3
                                    : isPending
                                    ? 0.16
                                    : 0.1,
                              ),
                              width: 1.2,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  isPending
                                      ? l10n.networkTesting
                                      : latency != null
                                      ? '$latency ms'
                                      : l10n.networkTimeout,
                                  style: tt.labelMedium?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
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
      setState(() {
        _latencyResults[index]?[host] = latency;
        _pendingLatencyHosts.remove(_latencyHostKey(index, host));
      });
    }

    setState(() {
      _testingLatency = true;
      _latencyExpanded = true;
      _latencyResults = pendingResults;
      _pendingLatencyHosts = pendingHosts;
    });
    try {
      final results = await Future.wait([
        api.network
            .testRouteLatency(
              0,
              onHostResult: (host, latency) =>
                  updateHostLatency(0, host, latency),
            )
            .then((r) => MapEntry(0, r)),
        api.network
            .testRouteLatency(
              1,
              onHostResult: (host, latency) =>
                  updateHostLatency(1, host, latency),
            )
            .then((r) => MapEntry(1, r)),
        api.network
            .testExtraApiLatency(
              onHostResult: (host, latency) =>
                  updateHostLatency(-1, host, latency),
            )
            .then((r) => MapEntry(-1, r)),
      ]);
      final latencyResults = Map<int, Map<String, int?>>.fromEntries(results);
      final bestRoute = _bestLatencyRoute(latencyResults);
      if (bestRoute != null && bestRoute != _user.apiRoute) {
        await _user.setApiRoute(bestRoute);
      }
      if (!mounted) return;
      setState(() {
        _testingLatency = false;
        _latencyResults = latencyResults;
        _pendingLatencyHosts = {};
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testingLatency = false;
        _pendingLatencyHosts = {};
      });
    }
  }

  Future<void> _refreshSystemProxy() async {
    setState(() => _refreshingSystemProxy = true);
    final proxy = await NetworkProxy.refreshSystemProxy();
    if (!mounted) return;
    setState(() => _refreshingSystemProxy = false);
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
    setState(_clearGoogleConnectivityResult);
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
      setState(() {
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
      setState(() {
        _latencyResults = {};
        _pendingLatencyHosts = {};
      });
    }
    _showToast(AppLocalizations.of(context)!.networkCopyAdvancedReset);
  }

  Future<void> _autoFillCopySettings() async {
    if (_autoFillingCopySettings) return;

    setState(() => _autoFillingCopySettings = true);

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
        setState(() => _autoFillingCopySettings = false);
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

  void _clearGoogleConnectivityResult() {
    _googleConnectivityOk = null;
    _googleConnectivityLatencyMs = null;
    _googleConnectivityMessage = null;
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
    setState(_clearGoogleConnectivityResult);
    _showToast(AppLocalizations.of(context)!.networkProxyEnabled(proxy.label));
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    showToast(context, message, isError: isError);
  }

  Future<void> _testGoogleConnectivity() async {
    if (_testingGoogleConnectivity) return;

    setState(() {
      _testingGoogleConnectivity = true;
      _clearGoogleConnectivityResult();
    });

    final uri = Uri.parse('https://www.google.com/generate_204');
    final proxyRule = NetworkProxy.findProxy(uri);
    final stopwatch = Stopwatch()..start();
    final client = NetworkProxy.createHttpClient(
      connectionTimeout: _googleConnectivityTimeout,
    );

    try {
      final request = await client
          .getUrl(uri)
          .timeout(_googleConnectivityTimeout);
      request.followRedirects = false;

      final response = await request.close().timeout(
        _googleConnectivityTimeout,
      );
      await response.drain<void>();
      stopwatch.stop();

      final statusCode = response.statusCode;
      final ok = statusCode >= 200 && statusCode < 400;
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _testingGoogleConnectivity = false;
        _googleConnectivityOk = ok;
        _googleConnectivityLatencyMs = stopwatch.elapsedMilliseconds;
        _googleConnectivityMessage = ok
            ? l10n.networkConnectionSuccess(statusCode, proxyRule)
            : l10n.networkConnectionFailed(statusCode, proxyRule);
      });
    } on TimeoutException {
      stopwatch.stop();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _testingGoogleConnectivity = false;
        _googleConnectivityOk = false;
        _googleConnectivityLatencyMs = stopwatch.elapsedMilliseconds;
        _googleConnectivityMessage = l10n.networkConnectionTimeout(proxyRule);
      });
    } on SocketException catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _testingGoogleConnectivity = false;
        _googleConnectivityOk = false;
        _googleConnectivityLatencyMs = stopwatch.elapsedMilliseconds;
        _googleConnectivityMessage = l10n.networkProxyRuleError(
          proxyRule,
          e.message,
        );
      });
    } catch (e) {
      stopwatch.stop();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _testingGoogleConnectivity = false;
        _googleConnectivityOk = false;
        _googleConnectivityLatencyMs = stopwatch.elapsedMilliseconds;
        _googleConnectivityMessage = l10n.networkTestFailed(
          proxyRule,
          e.toString(),
        );
      });
    } finally {
      client.close(force: true);
    }
  }
}

class _ConnectedButtonGroupItem {
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? loadingWidget;
  final String label;
  final bool isPrimary;

  const _ConnectedButtonGroupItem({
    this.onPressed,
    this.icon,
    this.loadingWidget,
    required this.label,
    this.isPrimary = false,
  });
}

class _ConnectedButtonGroup extends StatelessWidget {
  final List<_ConnectedButtonGroupItem> children;

  const _ConnectedButtonGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = BorderSide(color: cs.outline);

    return IntrinsicHeight(
      child: Row(
        children: List.generate(children.length, (i) {
          final item = children[i];
          final isFirst = i == 0;
          final isLast = i == children.length - 1;

          final shape = RoundedRectangleBorder(
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? const Radius.circular(8) : Radius.zero,
              right: isLast ? const Radius.circular(8) : Radius.zero,
            ),
          );

          final leftBorder = isFirst ? border : BorderSide.none;
          final rightBorder = isLast ? border : BorderSide.none;

          final effectiveBorder = Border(
            left: leftBorder,
            right: rightBorder,
            top: border,
            bottom: border,
          );

          final buttonWidget = TextButton(
            onPressed: item.onPressed,
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              shape: WidgetStateProperty.all(shape),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (item.isPrimary) return cs.primary;
                if (states.contains(WidgetState.disabled)) {
                  return cs.onSurface.withValues(alpha: 0.12);
                }
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (item.isPrimary) return cs.onPrimary;
                if (states.contains(WidgetState.disabled)) {
                  return cs.onSurface.withValues(alpha: 0.38);
                }
                return cs.onSurface;
              }),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return cs.onSurface.withValues(alpha: 0.12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return cs.onSurface.withValues(alpha: 0.08);
                }
                return null;
              }),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.loadingWidget != null)
                  item.loadingWidget!
                else if (item.icon != null)
                  Icon(item.icon, size: 18),
                const SizedBox(width: 6),
                Text(item.label),
              ],
            ),
          );

          return Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: effectiveBorder,
                borderRadius: shape.borderRadius,
              ),
              child: buttonWidget,
            ),
          );
        }),
      ),
    );
  }
}
