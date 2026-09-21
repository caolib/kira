part of '../ai_api.dart';

extension _AiSettingsProviders on AiSettings {
  AiProviderConfig _defaultZhipuProvider({
    String? apiKey,
    String? baseUrl,
    OpenAiApiFormat? apiFormat,
    String? model,
    List<String>? models,
  }) {
    final resolvedModel = model?.trim().isNotEmpty == true
        ? model!.trim()
        : AiSettings.defaultModel;
    final resolvedModels = _mergeModels(
      models?.isNotEmpty == true ? models! : AiSettings.availableModels,
      resolvedModel,
    );
    return AiProviderConfig(
      id: AiSettings.builtInZhipuProviderId,
      name: AiSettings._l10n.aiConfigZhipuName,
      baseUrl: baseUrl?.trim().isNotEmpty == true
          ? baseUrl!.trim()
          : AiSettings.defaultBaseUrl,
      apiKey: apiKey,
      apiFormat: apiFormat ?? OpenAiApiFormat.chatCompletions,
      model: resolvedModel,
      models: resolvedModels,
      isBuiltIn: true,
    );
  }

  List<String> _mergeModels(Iterable<String> models, String selected) {
    final result = <String>[];
    final seen = <String>{};
    for (final model in [...models, selected]) {
      final trimmed = model.trim();
      if (trimmed.isNotEmpty && seen.add(trimmed)) result.add(trimmed);
    }
    return result.isEmpty ? [AiSettings.defaultModel] : result;
  }

  Future<void> _loadProviders(
    SharedPreferences sp, {
    bool persistMigrations = true,
  }) async {
    final raw = sp.getString(AiSettings._keyProviders);
    var providers = <AiProviderConfig>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        providers = (jsonDecode(raw) as List)
            .map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>))
            .where((p) => p.id.trim().isNotEmpty)
            .toList();
      } catch (_) {
        providers = [];
      }
    }

    final legacyProvider = _defaultZhipuProvider(
      apiKey: _apiKey,
      baseUrl: _baseUrl,
      apiFormat: _apiFormat,
      model: _model,
      models: _customModels.isEmpty
          ? AiSettings.availableModels
          : _customModels,
    );
    final zhipuIndex = providers.indexWhere(
      (p) => p.id == AiSettings.builtInZhipuProviderId,
    );
    if (zhipuIndex < 0) {
      providers.insert(0, legacyProvider);
    } else {
      providers[zhipuIndex] = providers[zhipuIndex].copyWith(isBuiltIn: true);
    }
    _providers = providers;
    _activeProviderId =
        sp.getString(AiSettings._keyActiveProvider) ??
        AiSettings.builtInZhipuProviderId;
    if (_providers.every((p) => p.id != _activeProviderId)) {
      _activeProviderId = _providers.first.id;
    }
    final currentProvider = _providers
        .where((p) => p.id == _activeProviderId)
        .firstOrNull;
    if (currentProvider == null || !currentProvider.enabled) {
      _activeProviderId =
          _providers.where((p) => p.enabled).firstOrNull?.id ??
          _providers.first.id;
    }
    _syncActiveProviderFields();
    if (persistMigrations) await _saveProviders(sp);
  }

  void _syncActiveProviderFields() {
    final provider = activeProvider;
    _apiKey = provider.apiKey;
    _baseUrl = provider.baseUrl;
    _apiFormat = provider.apiFormat;
    _model = provider.model;
    _customModels = List.from(provider.models);
  }

  Future<void> _saveProviders([SharedPreferences? pref]) async {
    final sp = pref ?? await SharedPreferences.getInstance();
    await sp.setString(
      AiSettings._keyProviders,
      jsonEncode(_providers.map((e) => e.toJson()).toList()),
    );
    await sp.setString(AiSettings._keyActiveProvider, _activeProviderId);
    await sp.setString(AiSettings._keyBaseUrl, _baseUrl);
    await sp.setString(AiSettings._keyApiFormat, _apiFormat.name);
    await sp.setString(AiSettings._keyModel, _model);
    await sp.setStringList(AiSettings._keyCustomModels, _customModels);
    if (_apiKey?.trim().isNotEmpty == true) {
      await sp.setString(AiSettings._keyApiKey, _apiKey!.trim());
    } else {
      await sp.remove(AiSettings._keyApiKey);
    }
  }

  Future<void> _replaceProvider(AiProviderConfig provider) async {
    final idx = _providers.indexWhere((p) => p.id == provider.id);
    if (idx < 0) return;
    _providers[idx] = provider;
    if (_activeProviderId == provider.id) _syncActiveProviderFields();
    await _saveProviders();
  }
}
