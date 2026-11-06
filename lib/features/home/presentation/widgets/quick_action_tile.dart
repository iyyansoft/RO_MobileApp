import 'package:flutter/material.dart';

/// Clean, minimal quick-action card for the Home dashboard.
///
/// White card with a hairline border, a soft tinted icon circle, title and a
/// short subtitle. On hover (web/desktop) the border and arrow pick up the
/// accent colour and the card lifts slightly; it dips a touch while pressed.
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
    final radius = BorderRadius.circular(compact ? 14 : 16);
    final lift = _hovered && !_pressed ? -2.0 : 0.0;
    final scale = _pressed ? 0.985 : 1.0;

    final surface = isDark ? const Color(0xFF132233) : Colors.white;
    final border = _hovered
        ? accent.withValues(alpha: 0.45)
        : (isDark ? const Color(0xFF1E2D3D) : const Color(0xFFE6ECF2));
    final title = isDark ? Colors.white : const Color(0xFF0F172A);
    final muted = isDark ? Colors.white60 : const Color(0xFF64748B);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, lift, 0)
            ..scaleByDouble(scale, scale, 1, 1),
          transformAlignment: Alignment.center,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 11 : 14,
          ),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: radius,
            border: Border.all(color: border, width: 1),
            boxShadow: [
              BoxShadow(
                color: (_hovered ? accent : const Color(0xFF0F2850)).withValues(
                  alpha: isDark ? 0.18 : (_hovered ? 0.12 : 0.04),
                ),
                blurRadius: _hovered ? 18 : 8,
                offset: Offset(0, _hovered ? 6 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Soft tinted icon circle.
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: compact ? 36 : 42,
                height: compact ? 36 : 42,
                decoration: BoxDecoration(
                  color: accent.withValues(
                    alpha: isDark ? 0.18 : (_hovered ? 0.16 : 0.10),
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  color: accent,
                  size: compact ? 18 : 21,
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: title,
                        fontSize: compact ? 12.5 : 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: muted,
                        fontSize: compact ? 10 : 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedSlide(
                duration: const Duration(milliseconds: 200),
                offset: Offset(_hovered ? 0.15 : 0, 0),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: compact ? 16 : 18,
                  color: _hovered
                      ? accent
                      : (isDark ? Colors.white30 : const Color(0xFFB4BFCC)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
