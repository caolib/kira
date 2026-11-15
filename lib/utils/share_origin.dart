import 'package:flutter/widgets.dart';

/// A non-empty on-screen popover anchor for iPad sharing.
Rect shareOrigin(BuildContext context) {
  final media = MediaQuery.of(context);
  final bounds = Offset.zero & media.size;
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.attached &&
      renderObject.hasSize) {
    final rectangle =
        renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final clipped = rectangle.intersect(bounds);
    if (clipped.left.isFinite &&
        clipped.top.isFinite &&
        clipped.width.isFinite &&
        clipped.height.isFinite &&
        clipped.width > 0 &&
        clipped.height > 0) {
      return clipped;
    }
  }
  // Used only when a source widget has left the render tree. The native
  // popover cannot accept Rect.zero, even if the device itself is not an iPad.
  return Rect.fromCenter(center: bounds.center, width: 1, height: 1);
}
