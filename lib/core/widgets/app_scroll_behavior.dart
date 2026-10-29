import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Preserve native scrolling while allowing click-and-drag in desktop previews.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
