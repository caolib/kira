part of '../appearance_page.dart';

class _DesktopFontCard extends StatefulWidget {
  final UserManager user;

  const _DesktopFontCard({required this.user});

  @override
  State<_DesktopFontCard> createState() => _DesktopFontCardState();
}

class _DesktopFontCardState extends State<_DesktopFontCard> {
  Future<List<String>>? _fontsFuture;
  bool _applying = false;

  Future<List<String>> _loadFonts() async {
    final list = SystemFonts().getFontList();
    final unique = <String>{...list}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return unique;
  }

  Future<void> _pickFont() async {
    _fontsFuture ??= _loadFonts();
    final selected = await showDialog<_FontPickResult>(
      context: context,
      builder: (ctx) => _FontPickerDialog(
        currentFont: widget.user.desktopFontFamily,
        fontsFuture: _fontsFuture!,
      ),
    );
    if (!mounted || selected == null) return;

    if (selected.useDefault) {
      await widget.user.setDesktopFontFamily('');
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appearanceDefaultFontRestored,
        );
      }
      return;
    }

    final name = selected.fontName;
    if (name == null || name.isEmpty) return;
    setState(() => _applying = true);
    try {
      final family = await SystemFonts().loadFont(name);
      final resolved = (family?.toString().isNotEmpty ?? false)
          ? family.toString()
          : name;
      await widget.user.setDesktopFontFamily(resolved);
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appearanceFontChanged(resolved),
        );
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppLocalizations.of(context)!.appearanceFontLoadFailed(e.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final current = widget.user.desktopFontFamily;
    final hasCustom = current.isNotEmpty;

    return Card(
      color: cs.surfaceBright,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.font_download_outlined, color: cs.onSurfaceVariant),
                const SizedBox(width: AppSpacing.lg),
                Text(l10n.appearanceAppFont),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Material(
              color: cs.surface,
              borderRadius: AppRadius.mdR,
              child: InkWell(
                borderRadius: AppRadius.mdR,
                onTap: _applying ? null : _pickFont,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.mdR,
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          hasCustom ? current : l10n.appearanceSystemDefault,
                          style: tt.bodyMedium?.copyWith(
                            fontFamily: hasCustom ? current : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_applying)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
