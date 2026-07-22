import 'package:flutter/material.dart';

/// Shared clipped surface for manga cover cards.
class ComicCardSurface extends StatelessWidget {
  final Widget child;

  const ComicCardSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: child,
    );
  }
}
