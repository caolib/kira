import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A compact, tappable「图标 + 文字」动作项,用于并排的动作行
/// (关于页的「仓库 / 反馈 / 日志」、设置页的「导出 / 导入」)。
///
/// 只负责内容与点击,不含背景与圆角 —— 与 [ListTile] 一样由
/// [SettingTileGroup] 包裹并裁剪水波纹,因此必须放在该组内使用。
class SettingActionTile extends StatelessWidget {
  const SettingActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  /// 前导图形 —— 通常是 [Icon],也可以是任意组件(如 SVG 品牌图标)。
  final Widget icon;
  final String label;

  /// 点击回调;传 null 表示禁用(不响应点击)。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 16,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                style: tt.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
