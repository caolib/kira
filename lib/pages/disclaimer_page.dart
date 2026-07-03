import 'package:flutter/material.dart';

const appDisclaimerItems = [
  '本应用（以下简称"本软件"）系独立开发的非官方第三方客户端，与任何内容平台、出版商或权利人均无隶属、合作或代理关系。',
  '本软件不生产、上传、存储、编辑、修改、推荐或预先审查任何具体内容。所有内容均来源于第三方平台公开接口或可访问资源，其合法性、准确性、完整性及合规性由相应内容提供方独立负责。',
  '本软件所展示的内容可能包含成人向、暴力、恐怖或其他不适宜未成年人浏览的信息。您确认您已年满 18 周岁，且您所在地法律法规允许您访问此类内容。如您不符合前述条件，请立即停止使用并卸载本软件。',
  '您应自行判断所浏览内容是否适合，并确保您的使用行为完全符合您所在地现行有效的法律法规。因您使用本软件而产生的一切法律后果由您自行承担。',
  '如任何第三方内容涉嫌侵犯他人合法权益或违反法律法规，权利人可通过本软件提供的联系方式向开发者发送有效通知，开发者将在合理期限内核实并采取必要措施。',
  '本软件按"现状"提供，开发者不对其功能性、可用性、准确性或可靠性作出任何明示或默示的保证。在任何情况下，开发者均不对因使用或无法使用本软件而产生的任何直接、间接、附带、特殊或后果性损害承担责任。',
];

const appDisclaimerFooter =
    '继续使用本软件，即表示您已仔细阅读、充分理解并同意接受上述全部条款的约束。如您不同意任一条款，请立即停止使用并卸载本软件。';

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('免责声明')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text(
            '请在使用本应用前仔细阅读以下声明：',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Card(
            color: cs.surfaceContainerLow,
            shadowColor: Colors.black.withValues(alpha: 0.08),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in appDisclaimerItems) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ', style: tt.bodyMedium),
                        Expanded(child: Text(item, style: tt.bodyMedium)),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    appDisclaimerFooter,
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
