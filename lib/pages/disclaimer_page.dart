import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';

List<String> appDisclaimerItems(AppLocalizations l10n) => [
  l10n.appDisclaimerItem1,
  l10n.appDisclaimerItem2,
  l10n.appDisclaimerItem3,
  l10n.appDisclaimerItem4,
  l10n.appDisclaimerItem5,
  l10n.appDisclaimerItem6,
];

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.disclaimerTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text(
            l10n.appDisclaimerIntro,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            color: cs.surfaceContainerLow,
            shadowColor: cs.shadow,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in appDisclaimerItems(l10n)) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: tt.bodyMedium),
                        Expanded(child: Text(item, style: tt.bodyMedium)),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.appDisclaimerFooter,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
