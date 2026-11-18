import 'package:flutter/material.dart';

const _active = Color(0xFF0B5FC4);
const _idle = Color(0xFFC8D3E1);
const _ink = Color(0xFF0F172A);

/// Dots + "01 / 06" counter shown under the carousel.
class HeroPagination extends StatelessWidget {
  const HeroPagination({
    super.key,
    required this.count,
    required this.index,
    required this.onSelect,
    this.isDark = false,
  });

  final int count;
  final int index;
  final ValueChanged<int> onSelect;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == index,
            label: 'Slide ${i + 1} of $count',
            child: GestureDetector(
              key: ValueKey('hero-dot-$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 10,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  width: i == index ? 28 : 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: i == index
                        ? _active
                        : (isDark ? Colors.white24 : _idle),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 18),
        Container(
          key: const ValueKey('hero-counter'),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF132233) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F2850).withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            '${two(index + 1)} / ${two(count)}',
            style: TextStyle(
              color: isDark ? Colors.white : _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// White circular arrow button that sits over the carousel's outer edge.
class HeroArrowButton extends StatefulWidget {
  const HeroArrowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 56,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  @override
  State<HeroArrowButton> createState() => _HeroArrowButtonState();
}

class _HeroArrowButtonState extends State<HeroArrowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: widget.size,
            height: widget.size,
            transform: Matrix4.diagonal3Values(
              _hover ? 1.06 : 1,
              _hover ? 1.06 : 1,
              1,
            ),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hover ? _active : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F2850)
                      .withValues(alpha: _hover ? 0.25 : 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.46,
              color: _hover ? Colors.white : const Color(0xFF0B2E59),
            ),
          ),
        ),
      ),
    );
  }
}
