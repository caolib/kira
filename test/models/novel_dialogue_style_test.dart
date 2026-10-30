import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kira/models/novel_dialogue_style.dart';

void main() {
  test(
    'defaults follow body color and weight with a ten percent black fill',
    () {
      const style = NovelDialogueStyle();
      expect(style.colorMode, NovelDialogueColorMode.body);
      expect(style.textColor, 0xFF476B83);
      expect(style.weight, NovelDialogueWeight.body);
      expect(style.backgroundEnabled, isTrue);
      expect(style.backgroundColor, 0xFF000000);
      expect(style.backgroundOpacity, 0.1);
      expect(NovelDialogueStyle.fromJson(const {}), style);
    },
  );

  test('missing dark fields use white while saved styles are kept', () {
    const dark = NovelDialogueStyle(
      backgroundColor: NovelDialogueStyle.defaultDarkBackgroundColor,
    );
    expect(NovelDialogueStyle.fromJson(const {}, defaults: dark), dark);
    final saved = NovelDialogueStyle.fromJson(const {
      'colorMode': 'automatic',
      'weight': 'medium',
      'backgroundEnabled': false,
      'backgroundColor': 0xFF7D94B0,
      'backgroundOpacity': 0.12,
    }, defaults: dark);
    expect(saved.colorMode, NovelDialogueColorMode.automatic);
    expect(saved.weight, NovelDialogueWeight.medium);
    expect(saved.backgroundEnabled, isFalse);
    expect(saved.backgroundColor, 0xFF7D94B0);
    expect(saved.backgroundOpacity, 0.12);
  });

  test('all fields round-trip and copy without changing the original', () {
    const base = NovelDialogueStyle();
    final changed = base.copyWith(
      colorMode: NovelDialogueColorMode.custom,
      textColor: 0xFF654321,
      weight: NovelDialogueWeight.bold,
      backgroundEnabled: true,
      backgroundColor: 0xFF123456,
      backgroundOpacity: 0.7,
    );
    expect(changed.toJson(), {
      'colorMode': 'custom',
      'textColor': 0xFF654321,
      'weight': 'bold',
      'backgroundEnabled': true,
      'backgroundColor': 0xFF123456,
      'backgroundOpacity': 0.7,
    });
    final restored = NovelDialogueStyle.fromJson(changed.toJson());
    expect(restored, changed);
    expect(restored.hashCode, changed.hashCode);
    expect(base.copyWith(), base);
    expect(base.weight, NovelDialogueWeight.body);
    for (final variant in [
      base.copyWith(colorMode: NovelDialogueColorMode.automatic),
      base.copyWith(textColor: 0xFF123456),
      base.copyWith(weight: NovelDialogueWeight.medium),
      base.copyWith(backgroundEnabled: false),
      base.copyWith(backgroundColor: 0xFF123456),
      base.copyWith(backgroundOpacity: 0.5),
    ]) {
      expect(variant, isNot(base));
      expect(variant.hashCode, isNot(base.hashCode));
    }
  });

  test('colors are opaque and invalid ARGB values use defaults', () {
    for (final color in [0, 0x123456, 0x77123456]) {
      final style = NovelDialogueStyle(
        textColor: color,
        backgroundColor: color,
      );
      expect(style.textColor, color | 0xFF000000);
      expect(style.backgroundColor, color | 0xFF000000);
    }
    for (final color in [-1, 0x100000000]) {
      final style = NovelDialogueStyle(
        textColor: color,
        backgroundColor: color,
      );
      expect(style.textColor, NovelDialogueStyle.defaultTextColor);
      expect(style.backgroundColor, NovelDialogueStyle.defaultBackgroundColor);
    }
  });

  test('opacity clamps safely including non-finite values', () {
    for (final (value, expected) in [
      (-1.0, 0.0),
      (0.0, 0.0),
      (0.24, 0.24),
      (1.0, 1.0),
      (2.0, 1.0),
      (double.negativeInfinity, 0.0),
      (double.infinity, 1.0),
      (double.nan, 0.1),
    ]) {
      final style = NovelDialogueStyle(backgroundOpacity: value);
      expect(style.backgroundOpacity, expected);
      expect(
        const NovelDialogueStyle().copyWith(backgroundOpacity: value),
        style,
      );
      expect(NovelDialogueStyle.fromJson({'backgroundOpacity': value}), style);
      expect(() => jsonEncode(style.toJson()), returnsNormally);
    }
  });

  test('malformed JSON uses safe defaults and enum names round-trip', () {
    final malformed = NovelDialogueStyle.fromJson(const {
      'colorMode': ['custom'],
      'textColor': {},
      'weight': 'w900',
      'backgroundEnabled': 'true',
      'backgroundColor': -1,
      'backgroundOpacity': 'opaque',
    });
    expect(malformed, const NovelDialogueStyle());
    for (final mode in NovelDialogueColorMode.values) {
      for (final weight in NovelDialogueWeight.values) {
        final style = NovelDialogueStyle(colorMode: mode, weight: weight);
        expect(NovelDialogueStyle.fromJson(style.toJson()), style);
      }
    }
    final numericStrings = NovelDialogueStyle.fromJson(const {
      'textColor': '1122867',
      'backgroundOpacity': '0.6',
    });
    expect(numericStrings.textColor, 0xFF112233);
    expect(numericStrings.backgroundOpacity, 0.6);
  });
}
