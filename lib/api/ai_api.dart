import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../utils/app_dio.dart';

/// Prompt preset item.
class PromptPreset {
  final String id;
  final String name;
  final String prompt;
  final bool isBuiltIn;

  const PromptPreset({
    required this.id,
    required this.name,
    required this.prompt,
    this.isBuiltIn = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'prompt': prompt,
    'isBuiltIn': isBuiltIn,
  };

  factory PromptPreset.fromJson(Map<String, dynamic> json) => PromptPreset(
    id: json['id'] as String,
    name: json['name'] as String,
    prompt: json['prompt'] as String,
    isBuiltIn: json['isBuiltIn'] as bool? ?? false,
  );

  PromptPreset copyWith({String? name, String? prompt}) => PromptPreset(
    id: id,
    name: name ?? this.name,
    prompt: prompt ?? this.prompt,
    isBuiltIn: isBuiltIn,
  );
}

enum AiAutoSummaryTiming { onOpen, afterPreload }

enum OpenAiApiFormat { chatCompletions, responses }

extension OpenAiApiFormatLabel on OpenAiApiFormat {
  String get label => switch (this) {
    OpenAiApiFormat.chatCompletions => 'Chat Completions',
    OpenAiApiFormat.responses => 'Responses',
  };
}

class AiProviderConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String? apiKey;
  final OpenAiApiFormat apiFormat;
  final String model;
  final List<String> models;
  final bool isBuiltIn;
  final bool enabled;

  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiFormat,
    required this.model,
    required this.models,
    this.apiKey,
    this.isBuiltIn = false,
    this.enabled = true,
  });

  bool get hasConfig =>
      (apiKey?.trim().isNotEmpty ?? false) && baseUrl.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'apiFormat': apiFormat.name,
    'model': model,
    'models': models,
    'isBuiltIn': isBuiltIn,
    'enabled': enabled,
  };

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) {
    final models =
        (json['models'] as List?)?.whereType<String>().toList() ?? [];
    final model = json['model'] as String? ?? AiSettings.defaultModel;
    return AiProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String? ?? AiSettings._l10n.aiConfigCustomProvider,
      baseUrl: json['baseUrl'] as String? ?? AiSettings.defaultBaseUrl,
      apiKey: json['apiKey'] as String?,
      apiFormat: AiSettings.parseApiFormatName(json['apiFormat'] as String?),
      model: model,
      models: models.isEmpty ? [model] : models,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  AiProviderConfig copyWith({
    String? name,
    String? baseUrl,
    Object? apiKey = _unset,
    OpenAiApiFormat? apiFormat,
    String? model,
    List<String>? models,
    bool? isBuiltIn,
    bool? enabled,
  }) => AiProviderConfig(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: identical(apiKey, _unset) ? this.apiKey : apiKey as String?,
    apiFormat: apiFormat ?? this.apiFormat,
    model: model ?? this.model,
    models: models ?? this.models,
    isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    enabled: enabled ?? this.enabled,
  );

  static const Object _unset = Object();
}

/// OpenAI-compatible model API client and local settings.
///
/// API keys and model choices are stored only in local SharedPreferences.
class AiSettings extends ChangeNotifier {
  static final AiSettings _instance = AiSettings._();
  factory AiSettings() => _instance;
  AiSettings._();

  static const _keyApiKey = 'zhipu_api_key';
  static const _keyBaseUrl = 'zhipu_base_url';
  static const _keyApiFormat = 'zhipu_api_format';
  static const _keyModel = 'zhipu_model';
  static const _keyProviders = 'ai_providers';
  static const _keyActiveProvider = 'ai_active_provider';
  static const _keySummaryEnabled = 'zhipu_summary_enabled';
  static const _keySpoilerAnalysis = 'zhipu_spoiler_analysis';
  static const _keyPresets = 'zhipu_prompt_presets';
  static const _keyActivePreset = 'zhipu_active_preset';
  static const _keyAutoSummary = 'zhipu_auto_summary';
  static const _keyAutoSummaryMin = 'zhipu_auto_summary_min';
  static const _keyAutoSummaryTiming = 'zhipu_auto_summary_timing';
  static const _keySummaryCollapsed = 'zhipu_summary_collapsed';
  static const _keySpoilerWarn = 'zhipu_spoiler_warn';
  static const _keyCustomModels = 'zhipu_custom_models';

  /// Common models; the first one is the default.
  static const availableModels = <String>[
    'glm-4-Flash-250414',
    'glm-4.5-flash',
    'glm-4.7-flash',
  ];

  static const defaultModel = 'glm-4.5-flash';
  static const defaultBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';
  static const builtInZhipuProviderId = 'zhipu_bigmodel';

  /// Built-in preset ID.
  static const presetBasicId = 'basic';

  /// Legacy built-in style preset IDs, kept only for migration.
  static const _legacyPresetSharpId = 'sharp';
  static const _legacyPresetWarmId = 'warm';

  /// Legacy built-in spoiler preset ID, kept only for migration.
  static const presetSpoilerId = 'spoiler';

  static AppLocalizations get _l10n {
    final locale = PlatformDispatcher.instance.locale;
    if (locale.languageCode == 'zh' && locale.scriptCode == 'Hant') {
      return lookupAppLocalizations(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      );
    }
    return lookupAppLocalizations(const Locale('zh'));
  }

  static String get _legacyDefaultPromptBasic =>
      _l10n.aiLegacyDefaultPromptBasic;
  static String get defaultPromptBasic => _l10n.aiDefaultPromptBasic;

  /// Requirements appended to the active prompt when spoiler analysis is enabled.
  static String get spoilerAnalysisPromptAppendix =>
      _l10n.aiSpoilerAnalysisPromptAppendix;

  /// Backward-compatible getter; spoiler analysis is now appended dynamically.
  static String get defaultPromptSpoiler =>
      '$defaultPromptBasic\n\n$spoilerAnalysisPromptAppendix';

  /// Backward-compatible getter.
  static String get defaultSummaryPrompt => defaultPromptBasic;

  static List<PromptPreset> get builtInPresets => [
    PromptPreset(
      id: presetBasicId,
      name: _l10n.aiPromptBasicName,
      prompt: defaultPromptBasic,
      isBuiltIn: true,
    ),
  ];

  String? _apiKey;
  String _baseUrl = defaultBaseUrl;
  OpenAiApiFormat _apiFormat = OpenAiApiFormat.chatCompletions;
  String _model = defaultModel;
  String _summaryPrompt = defaultPromptBasic;
  bool _loaded = false;
  bool _summaryEnabled = false;
  bool _spoilerAnalysis = false;
  bool _autoSummary = false;
  int _autoSummaryMin = 30;
  AiAutoSummaryTiming _autoSummaryTiming = AiAutoSummaryTiming.onOpen;
  bool _summaryCollapsed = true;
  bool _spoilerWarn = true;
  List<PromptPreset> _presets = List.from(builtInPresets);
  String _activePresetId = presetBasicId;
  List<String> _customModels = [];
  List<AiProviderConfig> _providers = [];
  String _activeProviderId = builtInZhipuProviderId;

  String? get apiKey => _apiKey;
  String get baseUrl => _baseUrl;
  OpenAiApiFormat get apiFormat => _apiFormat;
  String get model => _model;
  String get summaryPrompt => _summaryPrompt;
  bool get hasApiKey => activeProvider.hasConfig;
  bool get hasConfig => activeProvider.enabled && activeProvider.hasConfig;
  bool get summaryEnabled => _summaryEnabled;
  bool get spoilerAnalysis => _spoilerAnalysis;
  bool get autoSummary => _autoSummary;
  int get autoSummaryMin => _autoSummaryMin;
  AiAutoSummaryTiming get autoSummaryTiming => _autoSummaryTiming;
  bool get summaryCollapsed => _summaryCollapsed;
  bool get spoilerWarn => _spoilerWarn;
  List<PromptPreset> get presets => List.unmodifiable(_presets);
  String get activePresetId => _activePresetId;
  List<String> get customModels => List.unmodifiable(_customModels);
  List<AiProviderConfig> get providers => List.unmodifiable(_providers);
  List<AiProviderConfig> get enabledProviders => List.unmodifiable(
    _providers.where((p) => p.enabled && p.hasConfig && p.models.isNotEmpty),
  );
  String get activeProviderId => _activeProviderId;

  AiProviderConfig get activeProvider {
    if (_providers.isEmpty) return _defaultZhipuProvider();
    final enabled = _providers.where((p) => p.enabled).toList();
    final candidates = enabled.isEmpty ? _providers : enabled;
    return candidates.where((p) => p.id == _activeProviderId).firstOrNull ??
        candidates.first;
  }

  PromptPreset? get activePreset =>
      _presets.where((p) => p.id == _activePresetId).firstOrNull;

  Future<void> load() async {
    if (_loaded) return;
    final sp = await SharedPreferences.getInstance();
    _apiKey = sp.getString(_keyApiKey);
    _baseUrl = sp.getString(_keyBaseUrl) ?? defaultBaseUrl;
    _apiFormat = _parseApiFormat(sp.getString(_keyApiFormat));
    _model = sp.getString(_keyModel) ?? defaultModel;
    _summaryEnabled = sp.getBool(_keySummaryEnabled) ?? false;
    _spoilerAnalysis = sp.getBool(_keySpoilerAnalysis) ?? false;
    _autoSummary = sp.getBool(_keyAutoSummary) ?? false;
    _autoSummaryMin = sp.getInt(_keyAutoSummaryMin) ?? 30;
    _autoSummaryTiming = _parseAutoSummaryTiming(
      sp.getString(_keyAutoSummaryTiming),
    );
    _summaryCollapsed = sp.getBool(_keySummaryCollapsed) ?? true;
    _spoilerWarn = sp.getBool(_keySpoilerWarn) ?? true;
    _activePresetId = sp.getString(_keyActivePreset) ?? presetBasicId;
    _customModels = sp.getStringList(_keyCustomModels) ?? [];
    // Seed built-in models into the custom model list on first use.
    if (_customModels.isEmpty) {
      _customModels = List.from(availableModels);
      await sp.setStringList(_keyCustomModels, _customModels);
    }
    await _loadProviders(sp);
    await _loadPresets(sp);
    _syncPrompt();
    _loaded = true;
    notifyListeners();
  }

  static OpenAiApiFormat parseApiFormatName(String? value) {
    for (final format in OpenAiApiFormat.values) {
      if (format.name == value) return format;
    }
    return OpenAiApiFormat.chatCompletions;
  }

  AiAutoSummaryTiming _parseAutoSummaryTiming(String? value) {
    for (final timing in AiAutoSummaryTiming.values) {
      if (timing.name == value) return timing;
    }
    return AiAutoSummaryTiming.onOpen;
  }

  OpenAiApiFormat _parseApiFormat(String? value) {
    return parseApiFormatName(value);
  }

  AiProviderConfig _defaultZhipuProvider({
    String? apiKey,
    String? baseUrl,
    OpenAiApiFormat? apiFormat,
    String? model,
    List<String>? models,
  }) {
    final resolvedModel = model?.trim().isNotEmpty == true
        ? model!.trim()
        : defaultModel;
    final resolvedModels = _mergeModels(
      models?.isNotEmpty == true ? models! : availableModels,
      resolvedModel,
    );
    return AiProviderConfig(
      id: builtInZhipuProviderId,
      name: _l10n.aiConfigZhipuName,
      baseUrl: baseUrl?.trim().isNotEmpty == true
          ? baseUrl!.trim()
          : defaultBaseUrl,
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
    return result.isEmpty ? [defaultModel] : result;
  }

  Future<void> _loadProviders(SharedPreferences sp) async {
    final raw = sp.getString(_keyProviders);
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
      models: _customModels.isEmpty ? availableModels : _customModels,
    );
    final zhipuIndex = providers.indexWhere(
      (p) => p.id == builtInZhipuProviderId,
    );
    if (zhipuIndex < 0) {
      providers.insert(0, legacyProvider);
    } else {
      providers[zhipuIndex] = providers[zhipuIndex].copyWith(isBuiltIn: true);
    }
    _providers = providers;
    _activeProviderId =
        sp.getString(_keyActiveProvider) ?? builtInZhipuProviderId;
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
    await _saveProviders(sp);
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
      _keyProviders,
      jsonEncode(_providers.map((e) => e.toJson()).toList()),
    );
    await sp.setString(_keyActiveProvider, _activeProviderId);
    await sp.setString(_keyBaseUrl, _baseUrl);
    await sp.setString(_keyApiFormat, _apiFormat.name);
    await sp.setString(_keyModel, _model);
    await sp.setStringList(_keyCustomModels, _customModels);
    if (_apiKey?.trim().isNotEmpty == true) {
      await sp.setString(_keyApiKey, _apiKey!.trim());
    } else {
      await sp.remove(_keyApiKey);
    }
  }

  Future<void> _replaceProvider(AiProviderConfig provider) async {
    final idx = _providers.indexWhere((p) => p.id == provider.id);
    if (idx < 0) return;
    _providers[idx] = provider;
    if (_activeProviderId == provider.id) _syncActiveProviderFields();
    await _saveProviders();
  }

  Future<void> _loadPresets(SharedPreferences sp) async {
    final raw = sp.getString(_keyPresets);
    var migrated = false;
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => PromptPreset.fromJson(e as Map<String, dynamic>))
            .map((preset) {
              final migratedPreset = _migrateStoredPreset(preset);
              if (!identical(migratedPreset, preset)) migrated = true;
              return migratedPreset;
            })
            .where((preset) {
              final keep = _shouldKeepStoredPreset(preset);
              if (!keep) migrated = true;
              return keep;
            })
            .toList();
        // Ensure built-in presets always exist; saved copies override defaults.
        final ids = list.map((e) => e.id).toSet();
        for (final builtIn in builtInPresets) {
          if (!ids.contains(builtIn.id)) {
            list.insert(
              builtIn == builtInPresets[0] ? 0 : list.length,
              builtIn,
            );
            migrated = true;
          }
        }
        _presets = list;
      } catch (_) {
        _presets = List.from(builtInPresets);
        migrated = true;
      }
    } else {
      _presets = List.from(builtInPresets);
    }
    if (_activePresetId == presetSpoilerId ||
        _presets.every((preset) => preset.id != _activePresetId)) {
      _activePresetId = presetBasicId;
      migrated = true;
    }
    if (migrated) {
      await sp.setString(
        _keyPresets,
        jsonEncode(_presets.map((e) => e.toJson()).toList()),
      );
      await sp.setString(_keyActivePreset, _activePresetId);
    }
  }

  PromptPreset _migrateStoredPreset(PromptPreset preset) {
    if (preset.id == presetBasicId &&
        preset.isBuiltIn &&
        preset.prompt == _legacyDefaultPromptBasic) {
      return builtInPresets.first;
    }
    return preset;
  }

  bool _shouldKeepStoredPreset(PromptPreset preset) {
    final isLegacyBuiltInStyle =
        preset.id == _legacyPresetSharpId || preset.id == _legacyPresetWarmId;
    if (isLegacyBuiltInStyle &&
        (preset.isBuiltIn || preset.name == '毒辣风格' || preset.name == '温和风格')) {
      return false;
    }
    if (preset.id == presetSpoilerId &&
        (preset.isBuiltIn || preset.name == '带剧透分析的提示词')) {
      return false;
    }
    final isCurrentBuiltIn = builtInPresets.any(
      (builtIn) => builtIn.id == preset.id,
    );
    return !preset.isBuiltIn || isCurrentBuiltIn;
  }

  Future<void> _savePresets() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _keyPresets,
      jsonEncode(_presets.map((e) => e.toJson()).toList()),
    );
  }

  void _syncPrompt() {
    final preset = activePreset;
    final basePrompt = preset?.prompt.trim().isNotEmpty == true
        ? preset!.prompt.trim()
        : defaultPromptBasic;
    _summaryPrompt = _spoilerAnalysis
        ? '$basePrompt\n\n$spoilerAnalysisPromptAppendix'
        : basePrompt;
  }

  Future<void> setApiKey(String? key) async {
    final trimmed = key?.trim();
    final provider = activeProvider.copyWith(
      apiKey: trimmed == null || trimmed.isEmpty ? null : trimmed,
    );
    await _replaceProvider(provider);
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    await _replaceProvider(activeProvider.copyWith(baseUrl: trimmed));
    notifyListeners();
  }

  Future<void> setApiFormat(OpenAiApiFormat format) async {
    await _replaceProvider(activeProvider.copyWith(apiFormat: format));
    notifyListeners();
  }

  Future<void> setProviderConfig({
    String? name,
    required String baseUrl,
    required OpenAiApiFormat apiFormat,
    required String? apiKey,
  }) async {
    final trimmedBaseUrl = baseUrl.trim();
    final trimmedKey = apiKey?.trim();
    final provider = activeProvider.copyWith(
      name: name,
      baseUrl: trimmedBaseUrl.isEmpty ? null : trimmedBaseUrl,
      apiFormat: apiFormat,
      apiKey: trimmedKey == null || trimmedKey.isEmpty ? null : trimmedKey,
    );
    await _replaceProvider(provider);
    notifyListeners();
  }

  Future<void> setActiveProvider(String id) async {
    if (_providers.every((p) => p.id != id)) return;
    _activeProviderId = id;
    _syncActiveProviderFields();
    await _saveProviders();
    notifyListeners();
  }

  Future<void> setProviderEnabled(String id, bool enabled) async {
    final idx = _providers.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _providers[idx] = _providers[idx].copyWith(enabled: enabled);
    if (!enabled && _activeProviderId == id) {
      _activeProviderId =
          _providers.where((p) => p.enabled && p.id != id).firstOrNull?.id ??
          id;
    } else if (enabled &&
        !_providers.any((p) => p.id == _activeProviderId && p.enabled)) {
      _activeProviderId = id;
    }
    _syncActiveProviderFields();
    await _saveProviders();
    notifyListeners();
  }

  Future<void> upsertProvider(AiProviderConfig provider) async {
    final trimmedName = provider.name.trim().isEmpty
        ? _l10n.aiConfigCustomProvider
        : provider.name.trim();
    final trimmedModel = provider.model.trim().isEmpty
        ? defaultModel
        : provider.model.trim();
    final normalized = provider.copyWith(
      name: trimmedName,
      baseUrl: provider.baseUrl.trim(),
      apiKey: provider.apiKey?.trim().isEmpty == true
          ? null
          : provider.apiKey?.trim(),
      model: trimmedModel,
      models: _mergeModels(provider.models, trimmedModel),
    );
    final idx = _providers.indexWhere((p) => p.id == normalized.id);
    if (idx < 0) {
      _providers.add(normalized);
    } else {
      _providers[idx] = normalized;
    }
    if (_providers.where((p) => p.enabled).length == 1 && normalized.enabled) {
      _activeProviderId = normalized.id;
    }
    _syncActiveProviderFields();
    await _saveProviders();
    notifyListeners();
  }

  Future<void> removeProvider(String id) async {
    final provider = _providers.where((p) => p.id == id).firstOrNull;
    if (provider == null || provider.isBuiltIn || _providers.length <= 1) {
      return;
    }
    _providers.removeWhere((p) => p.id == id);
    if (_activeProviderId == id) _activeProviderId = _providers.first.id;
    _syncActiveProviderFields();
    await _saveProviders();
    notifyListeners();
  }

  Future<void> setModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    await _replaceProvider(
      activeProvider.copyWith(
        model: trimmed,
        models: _mergeModels(_customModels, trimmed),
      ),
    );
    notifyListeners();
  }

  Future<void> setActiveModel({
    required String providerId,
    required String model,
  }) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    final idx = _providers.indexWhere((p) => p.id == providerId);
    if (idx < 0) return;
    final provider = _providers[idx];
    if (!provider.enabled) return;
    _providers[idx] = provider.copyWith(
      model: trimmed,
      models: _mergeModels(provider.models, trimmed),
    );
    _activeProviderId = providerId;
    _syncActiveProviderFields();
    await _saveProviders();
    notifyListeners();
  }

  Future<void> setSummaryEnabled(bool enabled) async {
    _summaryEnabled = enabled;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keySummaryEnabled, enabled);
    notifyListeners();
  }

  Future<void> setAutoSummary(bool enabled) async {
    _autoSummary = enabled;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keyAutoSummary, enabled);
    notifyListeners();
  }

  Future<void> setAutoSummaryMin(int min) async {
    _autoSummaryMin = min < 1 ? 1 : min;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_keyAutoSummaryMin, _autoSummaryMin);
    notifyListeners();
  }

  Future<void> setAutoSummaryTiming(AiAutoSummaryTiming timing) async {
    _autoSummaryTiming = timing;
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyAutoSummaryTiming, timing.name);
    notifyListeners();
  }

  Future<void> setSummaryCollapsed(bool collapsed) async {
    _summaryCollapsed = collapsed;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keySummaryCollapsed, collapsed);
    notifyListeners();
  }

  Future<void> setSpoilerWarn(bool enabled) async {
    _spoilerWarn = enabled;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keySpoilerWarn, enabled);
    notifyListeners();
  }

  Future<void> setSpoilerAnalysis(bool enabled) async {
    _spoilerAnalysis = enabled;
    _syncPrompt();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_keySpoilerAnalysis, enabled);
    notifyListeners();
  }

  Future<void> setActivePreset(String id) async {
    if (_presets.every((p) => p.id != id)) return;
    _activePresetId = id;
    _syncPrompt();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyActivePreset, id);
    notifyListeners();
  }

  Future<void> updatePreset(String id, {String? name, String? prompt}) async {
    final idx = _presets.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _presets[idx] = _presets[idx].copyWith(name: name, prompt: prompt);
    _syncPrompt();
    await _savePresets();
    notifyListeners();
  }

  Future<void> resetPreset(String id) async {
    final builtIn = builtInPresets.where((p) => p.id == id).firstOrNull;
    if (builtIn == null) return;
    final idx = _presets.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    _presets[idx] = builtIn;
    _syncPrompt();
    await _savePresets();
    notifyListeners();
  }

  Future<void> addPreset(String name, String prompt) async {
    final id = 'custom_${DateTime.now().millisecondsSinceEpoch}';
    _presets.add(PromptPreset(id: id, name: name, prompt: prompt));
    _activePresetId = id;
    _syncPrompt();
    await _savePresets();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyActivePreset, _activePresetId);
    notifyListeners();
  }

  Future<void> removePreset(String id) async {
    final preset = _presets.where((p) => p.id == id).firstOrNull;
    if (preset == null || preset.isBuiltIn) return;
    _presets.removeWhere((p) => p.id == id);
    if (_activePresetId == id) {
      _activePresetId = presetBasicId;
    }
    _syncPrompt();
    await _savePresets();
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyActivePreset, _activePresetId);
    notifyListeners();
  }

  bool isPresetModified(String id) {
    final builtIn = builtInPresets.where((p) => p.id == id).firstOrNull;
    if (builtIn == null) return false;
    final current = _presets.where((p) => p.id == id).firstOrNull;
    if (current == null) return false;
    return current.prompt != builtIn.prompt || current.name != builtIn.name;
  }
}

class AiMessage {
  final String role;
  final String content;
  final String? reasoningContent;

  const AiMessage({
    required this.role,
    required this.content,
    this.reasoningContent,
  });

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
    role: json['role'] as String? ?? 'user',
    content: json['content'] as String? ?? '',
    reasoningContent:
        json['reasoningContent'] as String? ??
        json['reasoning_content'] as String?,
  );

  Map<String, dynamic> toJson({bool includeReasoning = false}) => {
    'role': role,
    'content': content,
    if (includeReasoning && reasoningContent?.trim().isNotEmpty == true)
      'reasoningContent': reasoningContent,
  };
}

class AiStreamChunk {
  final String text;
  final bool isReasoning;

  const AiStreamChunk({required this.text, this.isReasoning = false});
}

class AiApi {
  final Dio _dio = AppDio.create(
    source: 'ai_api',
    options: BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 5),
    ),
  );

  /// Fetches model IDs exposed by an OpenAI-compatible provider.
  Future<List<String>> fetchModels({
    required String apiKey,
    required String baseUrl,
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _modelsEndpointFor(baseUrl),
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ),
      cancelToken: cancelToken,
    );
    final rawModels = response.data?['data'];
    if (rawModels is! List) return const [];

    final result = <String>[];
    final seen = <String>{};
    for (final item in rawModels) {
      final id = switch (item) {
        final String value => value,
        final Map map => map['id'] as String?,
        _ => null,
      };
      final trimmed = id?.trim();
      if (trimmed != null && trimmed.isNotEmpty && seen.add(trimmed)) {
        result.add(trimmed);
      }
    }
    return result;
  }

  /// Calls the SSE stream and yields text deltas chunk by chunk.
  Stream<String> streamChat({
    required String apiKey,
    required String baseUrl,
    required OpenAiApiFormat apiFormat,
    required String model,
    required List<AiMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    await for (final chunk in streamChatChunks(
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiFormat: apiFormat,
      model: model,
      messages: messages,
      cancelToken: cancelToken,
    )) {
      if (!chunk.isReasoning) yield chunk.text;
    }
  }

  /// Calls the SSE stream and preserves reasoning deltas when available.
  Stream<AiStreamChunk> streamChatChunks({
    required String apiKey,
    required String baseUrl,
    required OpenAiApiFormat apiFormat,
    required String model,
    required List<AiMessage> messages,
    CancelToken? cancelToken,
  }) async* {
    final response = await _dio.post<ResponseBody>(
      _endpointFor(baseUrl, apiFormat),
      data: _requestBody(apiFormat, model, messages),
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          // Disable compression so Dio does not wait for a full body to decompress.
          'Accept-Encoding': 'identity',
          'Cache-Control': 'no-cache',
        },
      ),
      cancelToken: cancelToken,
    );

    // Streaming UTF-8 decoding preserves split multibyte chars and line breaks.
    final lines = response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data == '[DONE]') return;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        final chunk = _parseStreamChunk(json, apiFormat);
        if (chunk != null && chunk.text.isNotEmpty) yield chunk;
      } catch (_) {
        // Ignore individual malformed SSE lines.
      }
    }
  }

  String _modelsEndpointFor(String baseUrl) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/models')) return trimmed;
    return '$trimmed/models';
  }

  String _endpointFor(String baseUrl, OpenAiApiFormat apiFormat) {
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (apiFormat == OpenAiApiFormat.chatCompletions) {
      if (trimmed.endsWith('/chat/completions')) return trimmed;
      return '$trimmed/chat/completions';
    }
    if (trimmed.endsWith('/responses')) return trimmed;
    return '$trimmed/responses';
  }

  Map<String, dynamic> _requestBody(
    OpenAiApiFormat apiFormat,
    String model,
    List<AiMessage> messages,
  ) {
    if (apiFormat == OpenAiApiFormat.chatCompletions) {
      return {
        'model': model,
        'messages': messages.map((e) => e.toJson()).toList(),
        'stream': true,
      };
    }
    return {
      'model': model,
      'input': messages
          .map(
            (e) => {
              'role': e.role,
              'content': [
                {'type': 'input_text', 'text': e.content},
              ],
            },
          )
          .toList(),
      'stream': true,
    };
  }

  AiStreamChunk? _parseStreamChunk(
    Map<String, dynamic> json,
    OpenAiApiFormat apiFormat,
  ) {
    if (apiFormat == OpenAiApiFormat.responses) {
      final type = json['type'];
      final delta = json['delta'];
      if (type == 'response.output_text.delta' && delta is String) {
        return AiStreamChunk(text: delta);
      }
      if (type == 'response.refusal.delta' && delta is String) {
        return AiStreamChunk(text: delta);
      }
      if ((type == 'response.reasoning_summary_text.delta' ||
              type == 'response.reasoning_text.delta') &&
          delta is String) {
        return AiStreamChunk(text: delta, isReasoning: true);
      }
    }

    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;
    final delta = first['delta'];
    if (delta is Map) {
      final reasoning = _stringField(delta, const [
        'reasoning_content',
        'reasoning',
        'reasoningContent',
        'thinking',
      ]);
      if (reasoning != null) {
        return AiStreamChunk(text: reasoning, isReasoning: true);
      }
      final content = delta['content'];
      if (content is String) return AiStreamChunk(text: content);
    }
    final message = first['message'];
    if (message is Map) {
      final reasoning = _stringField(message, const [
        'reasoning_content',
        'reasoning',
        'reasoningContent',
        'thinking',
      ]);
      if (reasoning != null) {
        return AiStreamChunk(text: reasoning, isReasoning: true);
      }
      final content = message['content'];
      if (content is String) return AiStreamChunk(text: content);
    }
    return null;
  }

  String? _stringField(Map source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
