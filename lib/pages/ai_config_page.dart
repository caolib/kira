import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/ai_api.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../utils/network_error.dart';
import '../utils/toast.dart';

part 'ai_config/ai_config_bubbles.dart';
part 'ai_config/ai_config_models.dart';
part 'ai_config/ai_config_provider_dialogs.dart';

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

  /// extension part 文件里的成员不是 State 子类成员，不能直接调用受保护的
  /// [setState]，统一经由这个转发方法。
  void _setState(VoidCallback fn) => setState(fn);

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
      // Ignore corrupted history so the chat page can still open.
    }
  }

  Future<void> _saveSessions() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _sessionsKey,
      jsonEncode(_sessions.map((session) => session.toJson()).toList()),
    );
  }

  String _titleFromFirstMessage(String text, AppLocalizations l10n) {
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.isEmpty) return l10n.aiConfigNewChat;
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
      AppLocalizations.of(context)!,
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

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context)!;
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    if (!_settings.hasConfig) {
      showToast(context, l10n.aiConfigConfigureBaseUrlAndApiKey, isError: true);
      unawaited(_openProviderConfigDialog());
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
            content: l10n.aiConfigModelReturnedEmpty,
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
              ? l10n.aiConfigRequestFailed(msg)
              : l10n.aiConfigPartialResponseError(buffer.toString(), msg),
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
    return NetworkError.message(e, l10n: AppLocalizations.of(context)!);
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
    final l10n = AppLocalizations.of(context)!;
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
                            l10n.aiConfigSessionHistory,
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
                          label: Text(l10n.aiConfigNewSession),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            setState(() {
                              _sessions.clear();
                              _activeSessionId = null;
                              _messages.clear();
                            });
                            setLocal(() {});
                            await _saveSessions();
                          },
                          icon: const Icon(
                            Icons.delete_sweep_outlined,
                            size: 18,
                          ),
                          label: Text(l10n.aiConfigClearSessions),
                        ),
                        IconButton(
                          tooltip: l10n.closeButton,
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
                        l10n.aiConfigNoSessionHistory,
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
                                  ? l10n.aiConfigMessageCount(
                                      session.messages.length,
                                    )
                                  : preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: l10n.aiConfigDeleteSession,
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
    final l10n = AppLocalizations.of(context)!;
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
                          l10n.chapterCommentsSwitchModel,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.closeButton,
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
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final modelChoices = _modelChoices;
    final activeProvider = _settings.activeProvider;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.aiConfigTitle),
            if (modelChoices.isNotEmpty)
              InkWell(
                borderRadius: AppRadius.lgR,
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
            tooltip: l10n.aiConfigSessionHistory,
            icon: const Icon(Icons.history),
            onPressed: _openSessionHistory,
          ),
          IconButton(
            tooltip: l10n.aiConfigProviderConfig,
            icon: Icon(
              _settings.hasConfig ? Icons.key : Icons.key_off_outlined,
              color: _settings.hasConfig ? null : cs.error,
            ),
            onPressed: _openProviderConfigDialog,
          ),
          IconButton(
            tooltip: l10n.aiConfigClearChat,
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
                  hintText: l10n.aiConfigInputHint,
                  border: OutlineInputBorder(borderRadius: AppRadius.xlR),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  suffixIcon: _sending
                      ? IconButton(
                          onPressed: _stop,
                          icon: const Icon(Icons.stop),
                          tooltip: l10n.chapterCommentsStop,
                        )
                      : IconButton(
                          onPressed: _send,
                          icon: const Icon(Icons.send),
                          tooltip: l10n.aiConfigSend,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
