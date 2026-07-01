import 'package:flutter/material.dart';

class ComicHeroTags {
  const ComicHeroTags._();

  static const transitionDuration = Duration(milliseconds: 650);
  static const reverseTransitionDuration = Duration(milliseconds: 500);

  static String base({
    required String scope,
    required String pathWord,
    required int index,
  }) {
    return 'comicHero:$scope:$pathWord:$index';
  }

  static String cover(String base) => '$base:cover';

  static RectTween createRectTween(Rect? begin, Rect? end) {
    return RectTween(begin: begin, end: end);
  }
}
