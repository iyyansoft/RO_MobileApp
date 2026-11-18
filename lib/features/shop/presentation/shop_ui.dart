import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

/// Shop App design system: one light B2B dashboard look for every screen.
/// Presentation only — no data, API or business logic lives here.
abstract final class ShopColors {
  static const background = Color(0xFFF3F6FB);
  static const surface = Colors.white;
  static const border = Color(0xFFE3EAF3);
  static const borderStrong = Color(0xFFD3DEEB);
  static const subtle = Color(0xFFF7F9FC);
  static const ink = Color(0xFF13294B);
  static const body = Color(0xFF334A68);
  static const muted = Color(0xFF6B7F99);
  static const primary = AppColors.primaryLight;
  static const primarySoft = Color(0xFFEAF1FF);
  static const sidebar = Color(0xFF0E2340);
  static const sidebarMuted = Color(0xFF9FB3CE);
  static const success = Color(0xFF128A5C);
  static const warning = Color(0xFFC77A0E);
  static const danger = Color(0xFFD43B3B);
}

abstract final class ShopBreakpoints {
  /// Permanent sidebar.
  static const desktop = 1024.0;

  /// Icon rail + header; below this the mobile layout is used.
  static const tablet = 680.0;
}

/// Light theme used by every Shop screen (also captured by its dialogs).
ThemeData shopTheme() {
  final base = AppTheme.lightTheme;
  const radius = BorderRadius.all(Radius.circular(12));
  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );
  return base.copyWith(
    scaffoldBackgroundColor: ShopColors.background,
    colorScheme: base.colorScheme.copyWith(
      primary: ShopColors.primary,
      surface: ShopColors.surface,
      surfaceTint: Colors.transparent,
    ),
    dividerTheme: const DividerThemeData(
      color: ShopColors.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: const CardThemeData(
      color: ShopColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: ShopColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ShopColors.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: ShopColors.muted, fontSize: 14),
      hintStyle: const TextStyle(color: ShopColors.muted, fontSize: 14),
      prefixIconColor: ShopColors.muted,
      suffixIconColor: ShopColors.muted,
      border: outline(ShopColors.borderStrong),
      enabledBorder: outline(ShopColors.borderStrong),
      focusedBorder: outline(ShopColors.primary, 1.6),
      errorBorder: outline(ShopColors.danger),
      focusedErrorBorder: outline(ShopColors.danger, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ShopColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ShopColors.ink,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        side: const BorderSide(color: ShopColors.borderStrong),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ShopColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: ShopColors.surface,
      selectedColor: ShopColors.primary,
      side: const BorderSide(color: ShopColors.borderStrong),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        color: ShopColors.body,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      secondaryLabelStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      checkmarkColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: ShopColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: ShopColors.surface,
      foregroundColor: ShopColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ShopColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ShopColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: ShopColors.primarySoft,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11.5,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? ShopColors.primary
              : ShopColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? ShopColors.primary
              : ShopColors.muted,
        ),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: ShopColors.muted,
      titleTextStyle: TextStyle(
        color: ShopColors.ink,
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: TextStyle(color: ShopColors.muted, fontSize: 12.5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: ShopColors.primary,
      linearTrackColor: ShopColors.primarySoft,
    ),
  );
}

/// Horizontal page padding for the current width.
double shopGutter(double width) =>
    width >= ShopBreakpoints.desktop ? 28 : (width >= 600 ? 20 : 14);

/// Centres page content at a readable maximum width.
class ShopContent extends StatelessWidget {
  const ShopContent({
    required this.child,
    this.maxWidth = 1240,
    this.padding,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    ),
  );
}

/// White rounded panel with a hairline border and soft shadow.
class ShopPanel extends StatelessWidget {
  const ShopPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = ShopColors.surface,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: ShopColors.border),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0F2744),
          blurRadius: 16,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// Title + optional subtitle and trailing actions at the top of a page.
class ShopSectionHeader extends StatelessWidget {
  const ShopSectionHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ShopColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: const TextStyle(color: ShopColors.muted, fontSize: 13.5),
          ),
        ],
      ],
    );
    if (trailing == null) return text;
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 520
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 12), trailing!],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                trailing!,
              ],
            ),
    );
  }
}

/// Small rounded label, e.g. "Order #123" or "COD · Pending".
class ShopPill extends StatelessWidget {
  const ShopPill({
    required this.label,
    this.icon,
    this.color = ShopColors.body,
    this.background = ShopColors.subtle,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Centered empty-state message with an icon.
class ShopEmptyState extends StatelessWidget {
  const ShopEmptyState({
    required this.icon,
    required this.message,
    this.detail,
    super.key,
  });

  final IconData icon;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
            color: ShopColors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 30, color: ShopColors.primary),
        ),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ShopColors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ShopColors.muted, fontSize: 13),
          ),
        ],
      ],
    ),
  );
}

/// Column-header text used in item tables.
class ShopTableHeading extends StatelessWidget {
  const ShopTableHeading(this.text, {this.align = TextAlign.left, super.key});
  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    style: const TextStyle(
      color: ShopColors.muted,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    ),
  );
}

/// Initials avatar for vendors / employees.
class ShopAvatar extends StatelessWidget {
  const ShopAvatar({required this.name, this.size = 42, super.key});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final initials = words.isEmpty
        ? '?'
        : (words.length == 1
                  ? words.first.substring(0, 1)
                  : '${words[0][0]}${words[1][0]}')
              .toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE4EEFF), Color(0xFFD3E3FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: ShopColors.primary,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
