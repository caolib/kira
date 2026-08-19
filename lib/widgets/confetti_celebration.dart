import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_confetti/flutter_confetti.dart';

/// 检查评论列表中含"完结撒花"或"完结散花"的评论数是否超过阈值。
bool hasCompletionCelebration(List<String> comments, {int threshold = 10}) {
  var count = 0;
  for (final text in comments) {
    if (text.contains('完结撒花') || text.contains('完结散花')) {
      count++;
      if (count >= threshold) return true;
    }
  }
  return false;
}

// ──────────────────────────────────────────────
// 樱花雨：从顶部随机位置飘落
// ──────────────────────────────────────────────

/// 从屏幕顶部随机位置飘落 🌸 的樱花雨动画。
///
/// 使用 [flutter_confetti](https://pub.dev/packages/flutter_confetti) 包的
/// [Confetti.launch] 静态方法：首次 launch 创建 OverlayEntry 并返回
/// [ConfettiController]，之后用同一 controller 反复 [ConfettiController.launch]
/// 追加粒子，避免每帧新建 OverlayEntry 堆积。下完由 [onFinished] 移除。
///
/// 粒子靠重力下落（[startVelocity]=0），[randomX]=true 使每片在顶部随机横坐标
/// 出现，[driftVariance] 制造左右飘动，[spread]=360 全方向扩散。
Timer? showConfettiCelebration(
  BuildContext context, {
  Duration duration = const Duration(seconds: 5),
}) {
  // 发射总次数（≈持续时长 / 间隔）；100ms × 50 次 ≈ 5 秒
  final total = duration.inMilliseconds ~/ 100;
  var progress = 0;
  var isDone = false;
  ConfettiController? controller;

  final timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
    progress++;
    if (progress >= total) {
      t.cancel();
      isDone = true;
      return;
    }

    if (controller == null) {
      controller = Confetti.launch(
        context,
        options: const ConfettiOptions(
          particleCount: 2,
          // 无初速度，仅靠重力下落
          startVelocity: 0,
          spread: 360,
          ticks: 1000,
          gravity: 0.4,
          driftVariance: 0.6,
          scalar: 1.1,
          y: -0.05,
          randomX: true,
        ),
        particleBuilder: (index) => Emoji(emoji: '🌸'),
        onFinished: (overlayEntry) {
          if (isDone) {
            overlayEntry.remove();
          }
        },
      );
    } else {
      controller!.launch();
    }
  });
  return timer;
}
