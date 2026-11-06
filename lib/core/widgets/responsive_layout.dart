import 'package:flutter/material.dart';

/// Responsive breakpoints used across the unified RO Wholesale application.
class ResponsiveBreakpoints {
  ResponsiveBreakpoints._();

  static const double mobileMax = 767.0;
  static const double tabletMin = 768.0;
  static const double tabletMax = 1023.0;
  static const double desktopMin = 1024.0;
  static const double maxContentWidth = 1280.0;
}

enum ScreenType { mobile, tablet, desktop }

/// Helper extension on BuildContext for quick, clean responsive checks.
extension ResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;

  bool get isMobile => screenWidth < ResponsiveBreakpoints.tabletMin;
  bool get isTablet =>
      screenWidth >= ResponsiveBreakpoints.tabletMin &&
      screenWidth < ResponsiveBreakpoints.desktopMin;
  bool get isDesktop => screenWidth >= ResponsiveBreakpoints.desktopMin;
  bool get isWideScreen => screenWidth >= ResponsiveBreakpoints.tabletMin;

  ScreenType get screenType {
    if (screenWidth < ResponsiveBreakpoints.tabletMin) return ScreenType.mobile;
    if (screenWidth < ResponsiveBreakpoints.desktopMin) return ScreenType.tablet;
    return ScreenType.desktop;
  }
}

/// A wrapper that centers and constrains the content width on wide screens
/// while letting mobile screens fill 100% of their viewport.
class ResponsiveContentWrapper extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  const ResponsiveContentWrapper({
    super.key,
    required this.child,
    this.maxWidth = ResponsiveBreakpoints.maxContentWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding != null
            ? Padding(padding: padding!, child: child)
            : child,
      ),
    );
  }
}

/// A responsive builder that supplies the active [ScreenType] and constraints.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(
    BuildContext context,
    ScreenType screenType,
    BoxConstraints constraints,
  ) builder;

  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenType = context.screenType;
        return builder(context, screenType, constraints);
      },
    );
  }
}

