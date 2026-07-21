import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

class AcknowledgementPage extends StatelessWidget {
  const AcknowledgementPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutAcknowledgementTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text(
            l10n.acknowledgementThanksTitle,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAcknowledgementItem(
                    context,
                    icon: Icons.subtitles_rounded,
                    title: l10n.acknowledgementDandanplayTitle,
                    description: l10n.acknowledgementDandanplayDesc,
                    url: 'https://www.dandanplay.com/',
                  ),
                  const Divider(height: 24),
                  _buildAcknowledgementItem(
                    context,
                    icon: Icons.translate_rounded,
                    title: l10n.acknowledgementZhconvertTitle,
                    description: l10n.acknowledgementZhconvertDesc,
                    url: 'https://zhconvert.org/',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcknowledgementItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required String url,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: AppRadius.mdR,
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: AppRadius.mdR,
              ),
              child: Icon(icon, color: cs.onPrimaryContainer, size: 22),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
