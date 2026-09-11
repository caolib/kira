part of '../bookshelf_page.dart';

extension _BookshelfToolbar on _BookshelfPageState {
  void _setOrdering(BuildContext context, String ordering) {
    Navigator.pop(context);
    _setState(() => _ordering = ordering);
    _user.setBookshelfOrdering(ordering);
    _load(silent: true, force: true);
  }

  double _toolbarContentHeight(BuildContext context) {
    // top/bottom padding + chip 行。
    // FilterChip/ActionChip 在 M3 下实际约 40–48，预留一点防溢出。
    return 4.0 + 48.0 + 8.0;
  }

  Widget _buildToolbar(BuildContext context, double hp) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, 4, hp, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilterChip(
                label: Text(l10n.hasUpdate),
                selected: _showUpdateOnly,
                onSelected: _setShowUpdateOnly,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _cacheTimeLabel,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              ActionChip(
                avatar: const Icon(Icons.sort, size: 18),
                label: Text(
                  _BookshelfPageState._orderingLabel(
                    AppLocalizations.of(context)!,
                    _ordering,
                  ),
                ),
                onPressed: () => _showOrderingSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showOrderingSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(l10n.sortMethod, style: tt.titleMedium),
            ),
            _OrderingTile(
              icon: Icons.update,
              title: l10n.sortByUpdateTime,
              subtitle: l10n.sortByUpdateTimeDesc(l10n.comicLabel),
              selected: _ordering == ApiOrdering.datetimeUpdated,
              onTap: () => _setOrdering(context, ApiOrdering.datetimeUpdated),
            ),
            _OrderingTile(
              icon: Icons.bookmark_added,
              title: l10n.sortByFavoriteTime,
              subtitle: l10n.sortByFavoriteTimeDesc,
              selected: _ordering == ApiOrdering.datetimeModifier,
              onTap: () => _setOrdering(context, ApiOrdering.datetimeModifier),
            ),
            _OrderingTile(
              icon: Icons.history,
              title: l10n.sortByBrowseTime,
              subtitle: l10n.sortByBrowseTimeDesc,
              selected: _ordering == ApiOrdering.datetimeBrowse,
              onTap: () => _setOrdering(context, ApiOrdering.datetimeBrowse),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
