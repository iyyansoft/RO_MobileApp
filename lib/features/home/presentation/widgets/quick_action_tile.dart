import 'package:flutter/material.dart';

/// Premium quick-action card for the Home dashboard.
///
/// White card (20px radius, hairline border, soft shadow) with a tinted
/// gradient icon tile in the card's accent colour, a title, a one-line
/// description and an arrow chip. The whole card is one tap target.
///
/// * Wide layout ([compact] false): icon, text and arrow in one row.
/// * Compact layout (phones / 2-column grid): icon and arrow on top, text
///   below, so titles and descriptions are never squeezed.
///
/// Hover (web/desktop) lifts the card, tints the border and slides the arrow;
/// pressing scales it down slightly.
class QuickActionTile extends StatefulWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.compact = false,
    this.isDark = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  final bool compact;
  final bool isDark;

  @override
  State<QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<QuickActionTile> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final isDark = widget.isDark;
    final accent = widget.color;
    final active = _hovered && !_pressed;

    final surface = isDark ? const Color(0xFF132233) : Colors.white;
    final border = _hovered
        ? accent.withValues(alpha: 0.40)
        : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE3EAF3));
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = isDark ? Colors.white60 : const Color(0xFF64748B);
    final radius = BorderRadius.circular(20);

    final iconTile = Container(
      width: compact ? 42 : 48,
      height: compact ? 42 : 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 13 : 15),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: isDark ? 0.30 : 0.16),
            accent.withValues(alpha: isDark ? 0.16 : 0.07),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Icon(widget.icon, color: accent, size: compact ? 21 : 23),
    );

    final arrow = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: compact ? 28 : 30,
      height: compact ? 28 : 30,
      transform: Matrix4.translationValues(active ? 3 : 0, 0, 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? accent
            : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
      ),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: compact ? 15 : 16,
        color: active ? Colors.white : muted,
      ),
    );

    final title = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: compact ? 14 : 15,
        fontWeight: FontWeight.w700,
        color: titleColor,
        letterSpacing: -0.1,
      ),
    );
    final subtitle = Text(
      widget.subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: compact ? 12 : 12.5,
        fontWeight: FontWeight.w500,
        color: muted,
      ),
    );

    final content = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [iconTile, const Spacer(), arrow],
              ),
              const SizedBox(height: 14),
              title,
              const SizedBox(height: 3),
              subtitle,
            ],
          )
        : Row(
            children: [
              iconTile,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [title, const SizedBox(height: 3), subtitle],
                ),
              ),
              const SizedBox(width: 10),
              arrow,
            ],
          );

    return Semantics(
      button: true,
      label: '${widget.label}. ${widget.subtitle}',
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 140),
            scale: _pressed ? 0.97 : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(0, active ? -3 : 0, 0),
              padding: compact
                  ? const EdgeInsets.fromLTRB(14, 14, 14, 14)
                  : const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: radius,
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: (active ? accent : const Color(0xFF0F2850))
                        .withValues(
                          alpha: isDark ? 0.25 : (active ? 0.14 : 0.05),
                        ),
                    blurRadius: active ? 22 : 14,
                    offset: Offset(0, active ? 10 : 4),
                  ),
                ],
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
