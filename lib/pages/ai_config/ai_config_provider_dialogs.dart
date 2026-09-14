part of '../ai_config_page.dart';

extension _AiConfigProviderDialogs on _AiConfigPageState {
  Future<void> _openProviderConfigDialog() async {
    final l10n = AppLocalizations.of(context)!;
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
                          l10n.aiConfigProvidersTitle,
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await _openProviderEditor();
                          if (ctx.mounted) setLocal(() {});
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(l10n.aiConfigAdd),
                      ),
                    ],
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
                          l10n.aiConfigProviderSummary(
                            provider.models.length,
                            provider.apiFormat.label,
                            provider.baseUrl,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.aiConfigEdit,
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                await _openProviderEditor(provider: provider);
                                if (ctx.mounted) setLocal(() {});
                              },
                            ),
                            if (!provider.isBuiltIn)
                              IconButton(
                                tooltip: l10n.deleteButton,
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
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openProviderEditor({AiProviderConfig? provider}) async {
    final l10n = AppLocalizations.of(context)!;
    final editing = provider ?? _settings.activeProvider;
    final isNew = provider == null;
    const customPreset = 'custom';
    const zhipuPreset = AiSettings.builtInZhipuProviderId;
    const agnesPreset = 'agnes';
    const agnesBaseUrl = 'https://api.agnes-ai.cn/v1';
    var providerPreset =
        !isNew && editing.id == AiSettings.builtInZhipuProviderId
        ? zhipuPreset
        : customPreset;
    final nameCtrl = TextEditingController(text: isNew ? '' : editing.name);
    final baseUrlCtrl = TextEditingController(
      text: isNew ? '' : editing.baseUrl,
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
        nameCtrl.text = l10n.aiConfigZhipuName;
        baseUrlCtrl.text = AiSettings.defaultBaseUrl;
        apiFormat = OpenAiApiFormat.chatCompletions;
        models = List<String>.from(AiSettings.availableModels);
        selectedModel = AiSettings.defaultModel;
      });
    }

    void applyAgnesPreset(StateSetter setLocal) {
      setLocal(() {
        providerPreset = agnesPreset;
        nameCtrl.text = l10n.aiConfigAgnesName;
        baseUrlCtrl.text = agnesBaseUrl;
        apiFormat = OpenAiApiFormat.chatCompletions;
        models = [];
        selectedModel = '';
      });
    }

    bool canFetch() =>
        baseUrlCtrl.text.trim().isNotEmpty && apiKeyCtrl.text.trim().isNotEmpty;

    Future<void> addModel(StateSetter setLocal) async {
      final ctrl = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.aiConfigAddModel),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.aiConfigModelIdLabel,
              hintText: 'gpt-4o-mini',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(l10n.aiConfigAdd),
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
        showToast(context, l10n.aiConfigFillBaseUrlAndApiKey, isError: true);
        return;
      }

      List<String> fetched;
      try {
        fetched = await _api.fetchModels(baseUrl: baseUrl, apiKey: apiKey);
      } catch (e) {
        if (!mounted) return;
        showToast(
          context,
          l10n.aiConfigFetchModelsFailed(NetworkError.message(e, l10n: l10n)),
          isError: true,
        );
        return;
      }
      if (!mounted) return;
      if (fetched.isEmpty) {
        showToast(context, l10n.aiConfigNoAvailableModels, isError: true);
        return;
      }

      var modelFilter = '';
      final selected = models.toSet();
      final result = await showDialog<Set<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) {
            final visibleModels = fetched
                .where(
                  (model) => model.toLowerCase().contains(
                    modelFilter.trim().toLowerCase(),
                  ),
                )
                .toList();
            return AlertDialog(
              title: Text(l10n.aiConfigAddModel),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: l10n.aiConfigSearchModel,
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) =>
                          setDialog(() => modelFilter = value),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    CheckboxListTile(
                      dense: true,
                      value: selected.length == fetched.length,
                      tristate:
                          selected.isNotEmpty &&
                          selected.length < fetched.length,
                      title: Text(l10n.selectAll),
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
                        itemCount: visibleModels.length,
                        itemBuilder: (_, index) {
                          final model = visibleModels[index];
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
                  child: Text(l10n.cancelButton),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: Text(l10n.aiConfigAddSelected),
                ),
              ],
            );
          },
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
          title: Text(
            isNew ? l10n.aiConfigAddProvider : l10n.aiConfigEditProvider,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: providerPreset,
                  decoration: InputDecoration(
                    labelText: l10n.aiConfigProviderNameLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: customPreset,
                      child: Text(l10n.aiConfigCustomProvider),
                    ),
                    DropdownMenuItem(
                      value: zhipuPreset,
                      child: Text(l10n.aiConfigZhipuName),
                    ),
                    DropdownMenuItem(
                      value: agnesPreset,
                      child: Text(l10n.aiConfigAgnesName),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    if (value == zhipuPreset) {
                      applyZhipuPreset(setLocal);
                    } else if (value == agnesPreset) {
                      applyAgnesPreset(setLocal);
                    } else {
                      setLocal(() {
                        providerPreset = customPreset;
                        baseUrlCtrl.text = '';
                        models = [];
                        selectedModel = '';
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty ||
                            name == l10n.aiConfigZhipuName ||
                            name == l10n.aiConfigAgnesName) {
                          nameCtrl.text = '';
                        }
                      });
                    }
                  },
                ),
                if (providerPreset == customPreset) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.aiConfigCustomNameLabel,
                      hintText: l10n.aiConfigCustomNameHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: baseUrlCtrl,
                  onChanged: (_) => setLocal(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.openai.com/v1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: apiKeyCtrl,
                  onChanged: (_) => setLocal(() {}),
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
                if (providerPreset == zhipuPreset ||
                    providerPreset == agnesPreset) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => launchUrl(
                        Uri.parse(
                          providerPreset == zhipuPreset
                              ? 'https://open.bigmodel.cn/apikey/platform'
                              : 'https://platform.agnes-ai.cn/settings/apiKeys',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text(
                        providerPreset == zhipuPreset
                            ? l10n.aiConfigGetZhipuApiKey
                            : l10n.aiConfigGetAgnesApiKey,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<OpenAiApiFormat>(
                  initialValue: apiFormat,
                  decoration: InputDecoration(
                    labelText: l10n.aiConfigApiFormatLabel,
                    border: const OutlineInputBorder(),
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
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: models.contains(selectedModel)
                      ? selectedModel
                      : null,
                  decoration: InputDecoration(
                    labelText: l10n.aiConfigDefaultModelLabel,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    if (models.isEmpty)
                      DropdownMenuItem(child: Text(l10n.aiConfigNoSelection)),
                    ...models.map(
                      (model) =>
                          DropdownMenuItem(value: model, child: Text(model)),
                    ),
                  ],
                  onChanged: (value) {
                    setLocal(() => selectedModel = value ?? '');
                  },
                ),
                if (models.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final model in models)
                          InputChip(
                            label: Text(model),
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
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: Text(l10n.aiConfigAdd),
                        onPressed: () => addModel(setLocal),
                      ),
                      if (models.isNotEmpty)
                        ActionChip(
                          avatar: const Icon(Icons.clear_all, size: 18),
                          label: Text(l10n.aiConfigClear),
                          onPressed: () => setLocal(() {
                            models = [];
                            selectedModel = '';
                          }),
                        ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.cloud_download_outlined,
                          size: 18,
                        ),
                        label: Text(l10n.aiConfigFetch),
                        backgroundColor: canFetch()
                            ? Theme.of(ctx).colorScheme.primaryContainer
                            : null,
                        onPressed: canFetch()
                            ? () => fetchModels(setLocal)
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancelButton),
            ),
            FilledButton(
              onPressed: models.isEmpty
                  ? null
                  : () {
                      final model = selectedModel.trim();
                      final name = providerPreset == zhipuPreset
                          ? l10n.aiConfigZhipuName
                          : providerPreset == agnesPreset
                          ? l10n.aiConfigAgnesName
                          : nameCtrl.text.trim().isEmpty
                          ? (isNew ? l10n.aiConfigCustomProvider : editing.name)
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
                          models: {
                            ...models,
                            if (model.isNotEmpty) model,
                          }.toList(),
                          isBuiltIn: isNew ? false : editing.isBuiltIn,
                          enabled: isNew ? true : editing.enabled,
                        ),
                      );
                    },
              child: Text(l10n.commentSettingsSaveButton),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _settings.upsertProvider(result);
    if (mounted) showToast(context, l10n.aiConfigProviderSaved);
  }
}
