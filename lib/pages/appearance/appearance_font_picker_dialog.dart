part of '../appearance_page.dart';

class _FontPickResult {
  final bool useDefault;
  final String? fontName;

  const _FontPickResult.defaultFont() : useDefault = true, fontName = null;
  const _FontPickResult.named(String name)
    : useDefault = false,
      fontName = name;
}

class _FontPickerDialog extends StatefulWidget {
  final String currentFont;
  final Future<List<String>> fontsFuture;

  const _FontPickerDialog({
    required this.currentFont,
    required this.fontsFuture,
  });

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.appearanceChooseFont,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.appearanceSearchFont,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: AppRadius.mdR),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: FutureBuilder<List<String>>(
                  future: widget.fontsFuture,
                  builder: (ctx, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: ExpressiveLoadingIndicator(),
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Center(
                        child: Text(
                          l10n.appearanceFontLoadFailed(snap.error.toString()),
                          style: TextStyle(color: cs.error),
                        ),
                      );
                    }
                    final fonts = snap.data ?? const <String>[];
                    final lowerQuery = _query.toLowerCase();
                    final filtered = lowerQuery.isEmpty
                        ? fonts
                        : fonts
                              .where(
                                (f) => f.toLowerCase().contains(lowerQuery),
                              )
                              .toList();

                    return ListView.builder(
                      itemCount: filtered.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == 0) {
                          final selected = widget.currentFont.isEmpty;
                          return ListTile(
                            leading: Icon(
                              selected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: selected ? cs.primary : null,
                            ),
                            title: Text(l10n.appearanceSystemDefault),
                            onTap: () => Navigator.of(
                              context,
                            ).pop(const _FontPickResult.defaultFont()),
                          );
                        }
                        final name = filtered[i - 1];
                        final selected = name == widget.currentFont;
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: selected ? cs.primary : null,
                          ),
                          title: Text(name),
                          onTap: () => Navigator.of(
                            context,
                          ).pop(_FontPickResult.named(name)),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
