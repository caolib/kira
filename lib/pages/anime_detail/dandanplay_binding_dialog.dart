part of '../anime_detail_page.dart';

class _DandanplayBindingDialog extends StatefulWidget {
  final String initialKeyword;
  final DandanplayBindingRecord? currentBinding;
  final String pathWord;
  final String localTitle;
  final String? localUuid;

  const _DandanplayBindingDialog({
    required this.initialKeyword,
    required this.currentBinding,
    required this.pathWord,
    required this.localTitle,
    this.localUuid,
  });

  @override
  State<_DandanplayBindingDialog> createState() =>
      _DandanplayBindingDialogState();
}

class _DandanplayBindingDialogState extends State<_DandanplayBindingDialog> {
  late final TextEditingController _controller;
  final _api = DandanplayApi();
  List<DandanplayAnimeSearchItem> _results = [];
  bool _searching = false;
  bool _searched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKeyword);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_search());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final rawKeyword = _controller.text.trim();
    if (rawKeyword.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _searched = true;
      _error = null;
    });

    try {
      final keyword = await ChineseConverter.convertToSimplifiedChinese(
        rawKeyword,
      );
      if (!mounted) return;
      if (keyword != rawKeyword) {
        _controller.value = TextEditingValue(
          text: keyword,
          selection: TextSelection.collapsed(offset: keyword.length),
        );
      }
      final results = await _api.searchAnime(keyword);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _searching = false;
        _error = e.toString();
      });
    }
  }

  void _bind(DandanplayAnimeSearchItem item) {
    Navigator.pop(
      context,
      _DandanplayBindingDialogResult.bind(
        DandanplayBindingRecord(
          pathWord: widget.pathWord,
          localTitle: widget.localTitle,
          localUuid: widget.localUuid,
          animeId: item.animeId,
          bangumiId: item.bangumiId,
          animeTitle: item.animeTitle,
          imageUrl: item.imageUrl,
          boundAt: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogHeight = (size.height * 0.68).clamp(360.0, 620.0);

    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.animeDetailBindDanmaku),
      content: SizedBox(
        width: 540,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.currentBinding != null) ...[
              _CurrentDandanplayBinding(record: widget.currentBinding!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: l10n.dandanplayBindingSearchKeyword,
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  tooltip: l10n.searchTabLabel,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildResults()),
          ],
        ),
      ),
      actions: [
        if (widget.currentBinding != null)
          TextButton.icon(
            onPressed: () => Navigator.pop(
              context,
              const _DandanplayBindingDialogResult.clear(),
            ),
            icon: const Icon(Icons.link_off_rounded),
            label: Text(l10n.dandanplayBindingClear),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.closeButton),
        ),
      ],
    );
  }

  Widget _buildResults() {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          l10n.dandanplayBindingSearchFailed(_error!),
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: cs.error),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _searched
              ? l10n.dandanplayBindingNoResults
              : l10n.dandanplayBindingSearchInstruction,
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        itemCount: _results.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: cs.outlineVariant),
        itemBuilder: (_, index) {
          final item = _results[index];
          final selected = widget.currentBinding?.animeId == item.animeId;
          return _DandanplayAnimeResultTile(
            item: item,
            selected: selected,
            hasBinding: widget.currentBinding != null,
            onTap: selected ? null : () => _bind(item),
          );
        },
      ),
    );
  }
}

class _CurrentDandanplayBinding extends StatelessWidget {
  final DandanplayBindingRecord record;

  const _CurrentDandanplayBinding({required this.record});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.dandanplayBindingCurrent,
                  style: tt.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  record.animeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '#${record.animeId}',
            style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _DandanplayAnimeResultTile extends StatelessWidget {
  final DandanplayAnimeSearchItem item;
  final bool selected;
  final bool hasBinding;
  final VoidCallback? onTap;

  const _DandanplayAnimeResultTile({
    required this.item,
    required this.selected,
    required this.hasBinding,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final imageUrl = item.imageUrl?.trim() ?? '';
    final meta = _metaText(l10n);

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.24)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: imageUrl.isEmpty
                    ? Container(
                        width: 52,
                        height: 72,
                        color: cs.surfaceContainerHighest,
                        child: Icon(
                          Icons.movie_outlined,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    : CoverBrightnessFilter(
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 52,
                          height: 72,
                          fit: BoxFit.cover,
                          placeholder: (_, _) =>
                              Container(color: cs.surfaceContainerHighest),
                          errorWidget: (_, _, _) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.animeTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: onTap,
                        icon: Icon(
                          selected ? Icons.check_rounded : Icons.link_rounded,
                          size: 16,
                        ),
                        label: Text(
                          selected
                              ? l10n.dandanplayBindingBound
                              : (hasBinding
                                    ? l10n.animeDetailRebind
                                    : l10n.dandanplayBindingBind),
                        ),
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaText(AppLocalizations l10n) {
    final parts = <String>[
      if ((item.typeDescription ?? '').isNotEmpty) item.typeDescription!,
      if (item.episodeCount > 0) l10n.totalEpisodes(item.episodeCount),
      if (item.rating > 0)
        l10n.dandanplayBindingRating(item.rating.toStringAsFixed(1)),
      ?_startYear,
    ];
    return parts.join(' · ');
  }

  String? get _startYear {
    final value = item.startDate;
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value)?.year.toString();
  }
}
