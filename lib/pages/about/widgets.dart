part of '../about_page.dart';

class SettingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const SettingIcon({super.key, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: AppRadius.mdR,
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

// ── 关于页 ──

/// Inline update card rendered on the About page. Replaces the old modal
/// update dialog — listens to [AppUpdateService.state] and surfaces an
/// available update as an embedded card.
class _UpdateCard extends StatefulWidget {
  const _UpdateCard({required this.onCheckUpdate});

  final VoidCallback onCheckUpdate;

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}
