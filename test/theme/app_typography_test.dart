import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/theme/app_typography.dart';

void main() {
  test('combines app font size with platform accessibility scaling', () {
    const platformTextScaler = TextScaler.linear(1.25);

    final scaled = AppTypography.composeTextScaler(platformTextScaler, 20 / 14);

    expect(scaled.scale(14), closeTo(25, 0.001));
  });

  test('returns the platform text scaler at the default factor', () {
    const platformTextScaler = TextScaler.linear(1.25);

    expect(
      identical(
        AppTypography.composeTextScaler(platformTextScaler, 1),
        platformTextScaler,
      ),
      isTrue,
    );
  });
}
