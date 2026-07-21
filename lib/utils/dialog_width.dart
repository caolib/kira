import 'package:flutter/material.dart';

/// Caps a dialog content width to the smaller of [maxWidth] and the viewport,
/// so fixed widths (e.g. 420) never overflow / force horizontal scroll on
/// narrow phones or split-screen.
///
/// Typical use in `AlertDialog.content`:
///   SizedBox(width: dialogContentWidth(context, 420), child: ...)
double dialogContentWidth(BuildContext context, double maxWidth) {
  final available =
      MediaQuery.sizeOf(context).width - 56; // 28dp gutter each side
  return available < maxWidth ? available : maxWidth;
}
