import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/ai_api.dart';
import '../utils/network_error.dart';
import '../utils/toast.dart';

class _AiModelChoice {
  final String providerId;
  final String providerName;
  final String model;

  const _AiModelChoice({
    required this.providerId,
    required this.providerName,
    required this.model,
  });

  String get value => '$providerId::$model';
}

class _AiChatSession {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<AiMessage> messages;

  const _AiChatSession({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages
        .map((message) => message.toJson(includeReasoning: true))
        .toList(),
  };

  factory _AiChatSession.fromJson(Map<String, dynamic> json) {
    final messages = (json['messages'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => AiMessage.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return _AiChatSession(
      id: json['id'] as String? ?? _newSessionId(),
      title: json['title'] as String? ?? '新对话',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: messages,
    );
  }

  _AiChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<AiMessage>? messages,
  }) => _AiChatSession(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
  );
}

String _newSessionId() => 'session_${DateTime.now().millisecondsSinceEpoch}';

class AiConfigPage extends StatefulWidget {
  const AiConfigPage({super.key});

  @override
  State<AiConfigPage> createState() => _AiConfigPageState();
}

class _AiConfigPageState extends State<AiConfigPage> {
  static const _sessionsKey = 'ai_chat_sessions';

  final _settings = AiSettings();
  final _api = AiApi();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<AiMessage> _messages = [];
  final Set<int> _expandedReasoningIndexes = {};
  List<_AiChatSession> _sessions = [];
  String? _activeSessionId;
  bool _sending = false;
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _settings.load();
    _loadSessions();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _settings.removeListener(_onSettingsChanged);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  List<_AiModelChoice> get _modelChoices {
    final result = <_AiModelChoice>[];
    for (final provider in _settings.enabledProviders) {
      final seen = <String>{};
      for (final model in provider.models) {
        final trimmed = model.trim();
        if (trimmed.isEmpty || !seen.add(trimmed)) continue;
        result.add(
          _AiModelChoice(
            providerId: provider.id,
            providerName: provider.name,
            model: trimmed,
          ),
        );
      }
    }
    return result;
  }

  Future<void> _loadSessions() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final sessions =
          (jsonDecode(raw) as List)
              .whereType<Map>()
              .map(
                (item) =>
                    _AiChatSession.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((session) => session.messages.isNotEmpty)
              .toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (_) {
      // 忽略损坏的历史记录，避免影响聊天页打开。
    }
  }

  Future<void> _saveSessions() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _sessionsKey,
      jsonEncode(_sessions.map((session) => session.toJson()).toList()),
    );
  }

  String _titleFromFirstMessage(String text) {
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.isEmpty) return '新对话';
    return singleLine.length > 18
        ? '${singleLine.substring(0, 18)}…'
        : singleLine;
  }

  Future<void> _persistCurrentSession() async {
    final savedMessages = _messages
        .where((message) => message.content.trim().isNotEmpty)
        .toList(growable: false);
    if (savedMessages.isEmpty) return;
    final firstUser = savedMessages
        .where((message) => message.role == 'user')
        .firstOrNull
        ?.content;
    final title = _titleFromFirstMessage(
      firstUser ?? savedMessages.first.content,
    );
    final now = DateTime.now();
    final id = _activeSessionId ?? _newSessionId();
    _activeSessionId = id;
    final session = _AiChatSession(
      id: id,
      title: title,
      updatedAt: now,
      messages: savedMessages,
    );
    final index = _sessions.indexWhere((item) => item.id == id);
    if (index < 0) {
      _sessions.insert(0, session);
    } else {
      _sessions[index] = session;
      _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    await _saveSessions();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _openProviderConfigDialog() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final providers = _settings.providers;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'AI 供应商',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await _openProviderEditor();
                          if (ctx.mounted) setLocal(() {});
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新增'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '支持任何 OpenAI 兼容接口；智谱清言作为内置预设保留，可为不同供应商分别保存 Base URL、API Key、模型和接口格式。',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const Divider(height: 24),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: providers.length,
                    itemBuilder: (_, i) {
                      final provider = providers[i];
                      return ListTile(
                        leading: Switch(
                          value: provider.enabled,
                          onChanged: (enabled) async {
                            await _settings.setProviderEnabled(
                              provider.id,
                              enabled,
                            );
                            if (ctx.mounted) setLocal(() {});
                          },
                        ),
                        title: Text(provider.name),
                        subtitle: Text(
                          '${provider.enabled ? '已启用' : '已禁用'} · ${provider.models.length} 个模型 · ${provider.apiFormat.label}\n${provider.baseUrl}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '编辑',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                await _openProviderEditor(provider: provider);
                                if (ctx.mounted) setLocal(() {});
                              },
                            ),
                            if (!provider.isBuiltIn)
                              IconButton(
                                tooltip: '删除',
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Theme.of(ctx).colorScheme.error,
                                ),
                                onPressed: () async {
                                  await _settings.removeProvider(provider.id);
                                  if (ctx.mounted) setLocal(() {});
                                },
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openProviderEditor({AiProviderConfig? provider}) async {
    final editing = provider ?? _settings.activeProvider;
    final isNew = provider == null;
    const customPreset = 'custom';
    const zhipuPreset = AiSettings.builtInZhipuProviderId;
    var providerPreset =
        !isNew && editing.id == AiSettings.builtInZhipuProviderId
        ? zhipuPreset
        : customPreset;
    final nameCtrl = TextEditingController(
      text: isNew ? '自定义供应商' : editing.name,
    );
    final baseUrlCtrl = TextEditingController(
      text: isNew ? 'https://api.openai.com/v1' : editing.baseUrl,
    );
    final apiKeyCtrl = TextEditingController(
      text: isNew ? '' : editing.apiKey ?? '',
    );
    var models = isNew
        ? <String>[]
        : <String>{
            ...editing.models,
            editing.model,
          }.where((m) => m.trim().isNotEmpty).map((m) => m.trim()).toList();
    var selectedModel = isNew ? '' : editing.model;
    if (selectedModel.isNotEmpty && !models.contains(selectedModel)) {
      models.add(selectedModel);
    }
    var apiFormat = isNew ? OpenAiApiFormat.chatCompletions : editing.apiFormat;
    var obscure = true;
    void applyZhipuPreset(StateSetter setLocal) {
      setLocal(() {
        providerPreset = zhipuPreset;
        nameCtrl.text = '智谱清言';
        baseUrlCtrl.text = AiSettings.defaultBaseUrl;
        apiFormat = OpenAiApiFormat.chatCompletions;
        models = List<String>.from(AiSettings.availableModels);
        selectedModel = AiSettings.defaultModel;
      });
    }

    Future<void> addModel(StateSetter setLocal) async {
      final ctrl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('添加模型'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '模型 ID',
              hintText: 'gpt-4o-mini',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('添加'),
            ),
          ],
        ),
      );
      if (result == null || result.trim().isEmpty) return;
      final model = result.trim();
      setLocal(() {
        if (!models.contains(model)) models = [...models, model];
        selectedModel = model;
      });
    }

    Future<void> fetchModels(StateSetter setLocal) async {
      final baseUrl = baseUrlCtrl.text.trim();
      final apiKey = apiKeyCtrl.text.trim();
      if (baseUrl.isEmpty || apiKey.isEmpty) {
        showToast(context, '请先填写 Base URL 和 API Key', isError: true);
        return;
      }

      List<String> fetched;
      try {
        fetched = await _api.fetchModels(baseUrl: baseUrl, apiKey: apiKey);
      } catch (e) {
        if (!mounted) return;
        showToast(context, '获取模型失败：${NetworkError.message(e)}', isError: true);
        return;
      }
      if (!mounted) return;
      if (fetched.isEmpty) {
        showToast(context, '未获取到可用模型', isError: true);
        return;
      }

      final selected = models.toSet();
      final result = await showDialog<Set<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: const Text('选择模型'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    dense: true,
                    value: selected.length == fetched.length,
                    tristate:
                        selected.isNotEmpty && selected.length < fetched.length,
                    title: const Text('全选'),
                    onChanged: (checked) {
                      setDialog(() {
                        selected.clear();
                        if (checked == true) selected.addAll(fetched);
                      });
                    },
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: fetched.length,
                      itemBuilder: (_, index) {
                        final model = fetched[index];
                        return CheckboxListTile(
                          dense: true,
                          value: selected.contains(model),
                          title: Text(model),
                          onChanged: (checked) {
                            setDialog(() {
                              if (checked == true) {
                                selected.add(model);
                              } else {
                                selected.remove(model);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('添加所选'),
              ),
            ],
          ),
        ),
      );
      if (result == null || result.isEmpty) return;
      setLocal(() {
        models = result.toList()..sort();
        if (!models.contains(selectedModel)) selectedModel = models.first;
      });
    }

    final result = await showDialog<AiProviderConfig>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isNew ? '新增供应商' : '编辑供应商'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: providerPreset,
                  decoration: const InputDecoration(
                    labelText: '供应商名称',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: customPreset,
                      child: Text('自定义供应商'),
                    ),
                    DropdownMenuItem(value: zhipuPreset, child: Text('智谱清言')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    if (value == zhipuPreset) {
                      applyZhipuPreset(setLocal);
                    } else {
                      setLocal(() {
                        providerPreset = customPreset;
                        baseUrlCtrl.text = 'https://api.openai.com/v1';
                        models = [];
                        selectedModel = '';
                        if (nameCtrl.text.trim().isEmpty ||
                            nameCtrl.text.trim() == '智谱清言') {
                          nameCtrl.text = '自定义供应商';
                        }
                      });
                    }
                  },
                ),
                if (providerPreset == customPreset) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '自定义名称',
                      hintText: 'OpenAI / One API / 自定义',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.openai.com/v1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<OpenAiApiFormat>(
                  initialValue: apiFormat,
                  decoration: const InputDecoration(
                    labelText: '接口格式',
                    border: OutlineInputBorder(),
                  ),
                  items: OpenAiApiFormat.values
                      .map(
                        (format) => DropdownMenuItem(
                          value: format,
                          child: Text(format.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setLocal(() => apiFormat = value);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: models.contains(selectedModel)
                      ? selectedModel
                      : null,
                  decoration: const InputDecoration(
                    labelText: '默认模型',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('未选择')),
                    ...models.map(
                      (model) =>
                          DropdownMenuItem(value: model, child: Text(model)),
                    ),
                  ],
                  onChanged: (value) {
                    setLocal(() => selectedModel = value ?? '');
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final model in models)
                        InputChip(
                          label: Text(model),
                          selected: model == selectedModel,
                          onSelected: (_) => setLocal(() {
                            selectedModel = model;
                          }),
                          onDeleted: () => setLocal(() {
                            models = models
                                .where((item) => item != model)
                                .toList();
                            if (selectedModel == model) {
                              selectedModel = models.isEmpty
                                  ? ''
                                  : models.first;
                            }
                          }),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('添加'),
                        onPressed: () => addModel(setLocal),
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.cloud_download_outlined,
                          size: 18,
                        ),
                        label: const Text('获取'),
                        onPressed: () => fetchModels(setLocal),
                      ),
                      if (models.isNotEmpty)
                        ActionChip(
                          avatar: const Icon(Icons.clear_all, size: 18),
                          label: const Text('清空'),
                          onPressed: () => setLocal(() {
                            models = [];
                            selectedModel = '';
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKeyCtrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setLocal(() => obscure = !obscure),
                    ),
                  ),
                ),
                if (providerPreset == zhipuPreset) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse('https://open.bigmodel.cn/apikey/platform'),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('获取智谱 API 密钥'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final model = selectedModel.trim();
                final name = providerPreset == zhipuPreset
                    ? '智谱清言'
                    : nameCtrl.text.trim().isEmpty
                    ? (isNew ? '自定义供应商' : editing.name)
                    : nameCtrl.text.trim();
                Navigator.pop(
                  ctx,
                  AiProviderConfig(
                    id: isNew
                        ? 'custom_${DateTime.now().millisecondsSinceEpoch}'
                        : editing.id,
                    name: name,
                    baseUrl: baseUrlCtrl.text.trim(),
                    apiKey: apiKeyCtrl.text.trim().isEmpty
                        ? null
                        : apiKeyCtrl.text.trim(),
                    apiFormat: apiFormat,
                    model: model,
                    models: {...models, if (model.isNotEmpty) model}.toList(),
                    isBuiltIn: isNew ? false : editing.isBuiltIn,
                    enabled: isNew ? true : editing.enabled,
                  ),
                );
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _settings.upsertProvider(result);
    if (mounted) showToast(context, '供应商已保存');
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_settings.hasConfig) {
      showToast(context, '请先配置 Base URL 和 API 密钥', isError: true);
      _openProviderConfigDialog();
      return;
    }

    _inputCtrl.clear();
    setState(() {
      _messages.add(AiMessage(role: 'user', content: text));
      _messages.add(const AiMessage(role: 'assistant', content: ''));
      _sending = true;
    });
    _scrollToBottom();
    await _persistCurrentSession();

    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    final history = _messages
        .sublist(0, _messages.length - 1)
        .where((m) => m.content.isNotEmpty || m.role == 'user')
        .toList();

    final buffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    try {
      final provider = _settings.activeProvider;
      final stream = _api.streamChatChunks(
        apiKey: provider.apiKey!,
        baseUrl: provider.baseUrl,
        apiFormat: provider.apiFormat,
        model: provider.model,
        messages: history,
        cancelToken: cancelToken,
      );
      await for (final chunk in stream) {
        if (!mounted) return;
        if (chunk.isReasoning) {
          reasoningBuffer.write(chunk.text);
        } else {
          buffer.write(chunk.text);
        }
        setState(() {
          _messages[_messages.length - 1] = AiMessage(
            role: 'assistant',
            content: buffer.toString(),
            reasoningContent: reasoningBuffer.isEmpty
                ? null
                : reasoningBuffer.toString(),
          );
        });
        _scrollToBottom();
      }
      if (buffer.isEmpty && mounted) {
        setState(() {
          _messages[_messages.length - 1] = AiMessage(
            role: 'assistant',
            content: '(模型未返回内容)',
            reasoningContent: reasoningBuffer.isEmpty
                ? null
                : reasoningBuffer.toString(),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = _extractError(e);
      setState(() {
        _messages[_messages.length - 1] = AiMessage(
          role: 'assistant',
          content: buffer.isEmpty
              ? '请求失败：$msg'
              : '${buffer.toString()}\n\n[出错：$msg]',
          reasoningContent: reasoningBuffer.isEmpty
              ? null
              : reasoningBuffer.toString(),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      _cancelToken = null;
      await _persistCurrentSession();
    }
  }

  String _extractError(Object e) {
    return NetworkError.message(e);
  }

  void _stop() {
    _cancelToken?.cancel('user_stop');
  }

  Future<void> _clearChat() async {
    if (_messages.isEmpty) return;
    await _persistCurrentSession();
    setState(() {
      _activeSessionId = null;
      _messages.clear();
    });
  }

  Future<void> _openSessionHistory() async {
    await _persistCurrentSession();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '会话历史',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _activeSessionId = null;
                              _messages.clear();
                            });
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('新会话'),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        '暂无历史会话',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _sessions.length,
                        itemBuilder: (_, index) {
                          final session = _sessions[index];
                          final selected = session.id == _activeSessionId;
                          final preview = session.messages
                              .where((message) => message.content.isNotEmpty)
                              .lastOrNull
                              ?.content
                              .replaceAll(RegExp(r'\s+'), ' ')
                              .trim();
                          return ListTile(
                            selected: selected,
                            leading: Icon(
                              selected
                                  ? Icons.chat_bubble
                                  : Icons.chat_bubble_outline,
                            ),
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              preview == null || preview.isEmpty
                                  ? '${session.messages.length} 条消息'
                                  : preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: '删除会话',
                              icon: Icon(Icons.delete_outline, color: cs.error),
                              onPressed: () async {
                                final removedActive =
                                    session.id == _activeSessionId;
                                setState(() {
                                  _sessions.removeWhere(
                                    (item) => item.id == session.id,
                                  );
                                  if (removedActive) {
                                    _activeSessionId = null;
                                    _messages.clear();
                                  }
                                });
                                setLocal(() {});
                                await _saveSessions();
                              },
                            ),
                            onTap: () {
                              setState(() {
                                _activeSessionId = session.id;
                                _messages
                                  ..clear()
                                  ..addAll(session.messages);
                              });
                              Navigator.pop(ctx);
                              _scrollToBottom();
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openModelPicker() async {
    final choices = _modelChoices;
    if (choices.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final active = _settings.activeProvider;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '切换模型',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: choices.length,
                    itemBuilder: (_, index) {
                      final choice = choices[index];
                      final showHeader =
                          index == 0 ||
                          choices[index - 1].providerId != choice.providerId;
                      final selected =
                          active.id == choice.providerId &&
                          active.model == choice.model;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showHeader) ...[
                            if (index > 0) const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                              child: Text(
                                choice.providerName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 24,
                            ),
                            title: Text(choice.model),
                            trailing: selected
                                ? Icon(Icons.check, color: cs.primary)
                                : null,
                            selected: selected,
                            onTap: () async {
                              await _settings.setActiveModel(
                                providerId: choice.providerId,
                                model: choice.model,
                              );
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final modelChoices = _modelChoices;
    final activeProvider = _settings.activeProvider;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 配置'),
            if (modelChoices.isNotEmpty)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _openModelPicker,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          activeProvider.model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_up,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '会话历史',
            icon: const Icon(Icons.history),
            onPressed: _openSessionHistory,
          ),
          IconButton(
            tooltip: '接口配置',
            icon: Icon(
              _settings.hasConfig ? Icons.key : Icons.key_off_outlined,
              color: _settings.hasConfig ? null : cs.error,
            ),
            onPressed: _openProviderConfigDialog,
          ),
          IconButton(
            tooltip: '清空对话',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _buildEmpty(cs)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) => _buildBubble(_messages[i], cs, i),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: '说点什么…',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon: _sending
                      ? IconButton(
                          onPressed: _stop,
                          icon: const Icon(Icons.stop),
                          tooltip: '停止',
                        )
                      : IconButton(
                          onPressed: _send,
                          icon: const Icon(Icons.send),
                          tooltip: '发送',
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: cs.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              _settings.hasConfig ? '开始一段对话吧' : '先在右上角配置接口',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(AiMessage msg, ColorScheme cs, int index) {
    final isUser = msg.role == 'user';
    final bg = isUser ? cs.primary : cs.surfaceContainerHighest;
    final fg = isUser ? cs.onPrimary : cs.onSurface;
    final reasoning = msg.reasoningContent?.trim();
    final hasReasoning = !isUser && reasoning != null && reasoning.isNotEmpty;
    final shouldCollapseReasoning = msg.content.trim().isNotEmpty;
    final reasoningExpanded =
        hasReasoning &&
        (!shouldCollapseReasoning || _expandedReasoningIndexes.contains(index));

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        child: GestureDetector(
          onLongPress: () async {
            if (msg.content.isEmpty) return;
            await Clipboard.setData(ClipboardData(text: msg.content));
            if (mounted) showToast(context, '已复制');
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasReasoning)
                  _buildReasoningBox(
                    reasoning,
                    cs,
                    expanded: reasoningExpanded,
                    collapsed: shouldCollapseReasoning,
                    onTap: shouldCollapseReasoning
                        ? () => setState(() {
                            if (_expandedReasoningIndexes.contains(index)) {
                              _expandedReasoningIndexes.remove(index);
                            } else {
                              _expandedReasoningIndexes.add(index);
                            }
                          })
                        : null,
                  ),
                if (hasReasoning && msg.content.isNotEmpty)
                  const SizedBox(height: 8),
                if (msg.content.isEmpty)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (isUser)
                  Text(msg.content, style: TextStyle(color: fg, fontSize: 15))
                else
                  MarkdownBody(
                    data: msg.content,
                    selectable: false,
                    onTapLink: (text, href, title) async {
                      if (href == null) return;
                      final uri = Uri.tryParse(href);
                      if (uri == null) return;
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    styleSheet: _markdownStyle(cs, fg),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReasoningBox(
    String reasoning,
    ColorScheme cs, {
    required bool expanded,
    required bool collapsed,
    VoidCallback? onTap,
  }) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant.withValues(alpha: 0.78),
      fontSize: 12,
      height: 1.35,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_alt_outlined,
                  size: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.78),
                ),
                const SizedBox(width: 4),
                Text(
                  expanded ? '思考过程' : '思考过程（已折叠）',
                  style: textStyle?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (collapsed) ...[
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.78),
                  ),
                ],
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 6),
              Text(reasoning, style: textStyle),
            ],
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyle(ColorScheme cs, Color fg) {
    final base = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: fg, fontSize: 15, height: 1.45);
    final codeBg = cs.surfaceContainerHigh;
    return MarkdownStyleSheet(
      p: base,
      h1: base?.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
      h2: base?.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
      h3: base?.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
      h4: base?.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
      strong: base?.copyWith(fontWeight: FontWeight.bold),
      em: base?.copyWith(fontStyle: FontStyle.italic),
      a: base?.copyWith(
        color: cs.primary,
        decoration: TextDecoration.underline,
      ),
      blockquote: base?.copyWith(color: cs.onSurfaceVariant),
      blockquoteDecoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      code: base?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: codeBg,
        fontSize: 14,
      ),
      codeblockDecoration: BoxDecoration(
        color: codeBg,
        borderRadius: BorderRadius.circular(8),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      listBullet: base,
      tableBody: base,
      tableHead: base?.copyWith(fontWeight: FontWeight.bold),
      tableBorder: TableBorder.all(color: cs.outlineVariant, width: 1),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 1)),
      ),
    );
  }
}
