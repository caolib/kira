import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/comic.dart' as comic_model;
import '../theme/app_radius.dart';

/// 漫画详情信息区的 chip 组件（作者/状态/地区/主题），供漫画详情页与
/// 本地漫画详情页共用，保证两处渲染一致。
class InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color textColor;
  const InfoChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.lgR),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthorChip extends StatelessWidget {
  final comic_model.Author author;
  final VoidCallback onTap;

  const AuthorChip({super.key, required this.author, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: cs.primaryContainer,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_outlined,
                size: 12,
                color: cs.onPrimaryContainer,
              ),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  author.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ThemeChip extends StatelessWidget {
  final comic_model.Theme theme;
  final VoidCallback onTap;
  final Color color;
  final Color textColor;

  const ThemeChip({
    super.key,
    required this.theme,
    required this.onTap,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: AppRadius.lgR,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgR,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.label_outline, size: 12, color: textColor),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  theme.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 热度数字格式化：≥1 亿显示 x.x亿，≥1 万显示 x.x万。
String formatPopularCount(BuildContext context, int n) {
  final l10n = AppLocalizations.of(context)!;
  if (n >= 100000000) {
    return l10n.hundredMillionUnit((n / 100000000).toStringAsFixed(1));
  }
  if (n >= 10000) {
    return l10n.tenThousandUnit((n / 10000).toStringAsFixed(1));
  }
  return n.toString();
}
