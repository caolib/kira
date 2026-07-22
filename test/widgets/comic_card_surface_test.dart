import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/widgets/comic_card_surface.dart';

void main() {
  testWidgets('comic cover card inherits the global CardTheme shadow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          cardTheme: const CardThemeData(
            elevation: 3.5,
            shadowColor: Colors.black,
          ),
        ),
        home: const SizedBox(
          width: 100,
          height: 150,
          child: ComicCardSurface(child: ColoredBox(color: Colors.white)),
        ),
      ),
    );

    final card = tester.widget<Card>(find.byType(Card));
    expect(card.elevation, isNull);
    expect(card.shadowColor, isNull);
    expect(card.shape, isNull);
    expect(card.surfaceTintColor, isNull);
  });
}
