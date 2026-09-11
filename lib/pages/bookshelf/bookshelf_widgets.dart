part of '../bookshelf_page.dart';

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: const BoxDecoration(
          color: AppStatusColors.updateAccent,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomLeft: Radius.circular(10),
          ),
        ),
        child: Text(
          AppLocalizations.of(context)!.updateBadge,
          style: AppTypography.meta(Theme.of(context).textTheme)?.copyWith(
            color: AppStatusColors.onUpdateAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class _OrderingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _OrderingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? cs.primary : null),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: selected ? Icon(Icons.check, color: cs.primary) : null,
      selected: selected,
      onTap: onTap,
    );
  }
}
