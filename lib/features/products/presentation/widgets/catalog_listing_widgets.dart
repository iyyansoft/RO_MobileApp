import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/category_model.dart';
import '../providers/product_provider.dart';

const _navy = Color(0xFF0B2E59);
const _blue = Color(0xFF0B4FB8);
const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF475569);
const _line = Color(0xFFDCE5F0);

/// Icon for a catalogue category (matched on its id / name).
IconData categoryIconFor(String idOrName) {
  final s = idOrName.toLowerCase();
  if (s.contains('sys') || s.contains('purifier')) return Icons.kitchen_rounded;
  if (s.contains('mem')) return Icons.layers_rounded;
  if (s.contains('filter') || s.contains('cartridge') || s.contains('flt')) {
    return Icons.filter_alt_rounded;
  }
  if (s.contains('pump') || s.contains('booster')) return Icons.speed_rounded;
  if (s.contains('pipe') || s.contains('tub')) return Icons.plumbing_rounded;
  if (s.contains('spare') || s.contains('valve') || s.contains('part')) {
    return Icons.settings_rounded;
  }
  return Icons.grid_view_rounded;
}

/// Water-themed page header: back button, "Categories" breadcrumb, category
/// icon, title and subtitle, with a painted water wave and leaves.
class CatalogHeader extends StatelessWidget {
  const CatalogHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onBack,
    required this.onBreadcrumb,
    required this.horizontalPadding,
    this.bottom,
    this.isDark = false,
  });

  /// Shown under the title inside the header (e.g. the search bar).
  final Widget? bottom;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onBack;
  final VoidCallback onBreadcrumb;
  final double horizontalPadding;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final ink = isDark ? Colors.white : _ink;
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _WaterHeaderPainter(isDark: isDark)),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            narrow ? 12 : 22,
            horizontalPadding,
            narrow ? 18 : 30,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CircleButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onTap: onBack,
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: onBreadcrumb,
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : _muted,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text(
                      'Categories',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: narrow ? 14 : 20),
              Row(
                children: [
                  Container(
                    width: narrow ? 58 : 84,
                    height: narrow ? 58 : 84,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF132233) : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F2850)
                              .withValues(alpha: 0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: _blue, size: narrow ? 28 : 40),
                  ),
                  SizedBox(width: narrow ? 14 : 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontSize: narrow ? 24 : 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : _muted,
                              fontSize: narrow ? 13.5 : 16,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Keep text clear of the water art on wide screens.
                  if (!narrow)
                    SizedBox(width: MediaQuery.sizeOf(context).width * 0.22),
                ],
              ),
              if (bottom != null) ...[
                SizedBox(height: narrow ? 18 : 28),
                bottom!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F2850).withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: _navy, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Light blue header wash with a flowing water wave, droplets and leaves on
/// the right.
class _WaterHeaderPainter extends CustomPainter {
  const _WaterHeaderPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final rect = Offset.zero & size;

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF0E1C2B), Color(0xFF0F2438)]
              : const [Color(0xFFF2F8FE), Color(0xFFE2F0FC), Color(0xFFD3E9FA)],
        ).createShader(rect),
    );
    if (w < 600) return; // Phones: just the wash.

    // Flowing water wave on the right.
    final x0 = w * 0.52;
    Path wave(double y, double amp, double phase) {
      final p = Path()..moveTo(x0, h * y);
      const steps = 40;
      for (var i = 0; i <= steps; i++) {
        final f = i / steps;
        final x = x0 + (w - x0) * f;
        final env = math.sin(f * math.pi); // taper at both ends
        p.lineTo(x, h * y - math.sin(f * math.pi * 2.2 + phase) * amp * env);
      }
      return p;
    }

    for (final (y, amp, phase, alpha, width) in [
      (0.62, 26.0, 0.4, 0.30, 26.0),
      (0.60, 22.0, 0.9, 0.45, 14.0),
      (0.58, 18.0, 1.4, 0.65, 6.0),
    ]) {
      canvas.drawPath(
        wave(y, amp, phase),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width
          ..shader = LinearGradient(
            colors: [
              const Color(0xFF3B9BE8).withValues(alpha: 0),
              const Color(0xFF2B87DD).withValues(alpha: alpha),
              const Color(0xFF7CC4F5).withValues(alpha: alpha),
              const Color(0xFF3B9BE8).withValues(alpha: 0),
            ],
            stops: const [0, 0.35, 0.7, 1],
          ).createShader(Rect.fromLTRB(x0, 0, w, h)),
      );
    }
    // Bright crest highlight.
    canvas.drawPath(
      wave(0.575, 18, 1.4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Droplets.
    final rnd = math.Random(3);
    for (var i = 0; i < 16; i++) {
      final x = x0 + (w - x0) * (0.25 + rnd.nextDouble() * 0.6);
      final y = h * (0.15 + rnd.nextDouble() * 0.35);
      final r = 1.8 + rnd.nextDouble() * 3.6;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = const Color(0xFF5AAEEC).withValues(alpha: 0.55),
      );
      canvas.drawCircle(
        Offset(x - r * 0.3, y - r * 0.3),
        r * 0.35,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }

    // Leaves.
    _leaf(canvas, Offset(w * 0.93, h * 0.48), h * 0.42, 0.75);
    _leaf(canvas, Offset(w * 0.90, h * 0.58), h * 0.30, 1.25);
    _leaf(canvas, Offset(w * 0.62, h * 0.70), h * 0.24, -1.15);
  }

  void _leaf(Canvas canvas, Offset base, double length, double angle) {
    final width = length * 0.36;
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angle);
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(width, -length * 0.45, 0, -length)
      ..quadraticBezierTo(-width * 0.85, -length * 0.5, 0, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFF1E7A34), Color(0xFF6CC24A), Color(0xFF9BDC6E)],
          stops: [0, 0.6, 1],
        ).createShader(Rect.fromLTRB(-width, -length, width, 0)),
    );
    canvas.drawLine(
      Offset.zero,
      Offset(0, -length * 0.9),
      Paint()
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WaterHeaderPainter old) => old.isDark != isDark;
}

/// One horizontal row of category chips ("All Products" first).
class CategoryChipBar extends StatelessWidget {
  const CategoryChipBar({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    required this.horizontalPadding,
    this.isDark = false,
  });

  final List<CategoryModel> categories;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final double horizontalPadding;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 4),
      child: Row(
        children: [
          _chip(null, 'All Products', null),
          for (final c in categories)
            _chip(c.id, c.name, categoryIconFor('${c.id} ${c.name}')),
        ],
      ),
    );
  }

  Widget _chip(String? id, String label, IconData? icon) {
    final selected = selectedId == id;
    final fg = selected ? Colors.white : (isDark ? Colors.white : _ink);
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Material(
        color: selected
            ? _blue
            : (isDark ? const Color(0xFF132233) : Colors.white),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected
                ? _blue
                : (isDark ? const Color(0xFF1E2D3D) : _line),
          ),
        ),
        child: InkWell(
          key: ValueKey('category-chip-${id ?? 'all'}'),
          customBorder: const StadiumBorder(),
          onTap: () => onSelect(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  )
                else if (icon != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(icon, size: 18, color: _blue),
                  ),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "N Products Found", grid/list toggle, sort and filter buttons.
class ListingToolbar extends StatelessWidget {
  const ListingToolbar({
    super.key,
    required this.count,
    required this.isGridView,
    required this.onViewChanged,
    required this.sortLabel,
    required this.onSort,
    required this.activeFilters,
    required this.onFilter,
    this.isDark = false,
  });

  final int count;
  final bool isGridView;
  final ValueChanged<bool> onViewChanged;
  final String sortLabel;
  final VoidCallback onSort;
  final int activeFilters;
  final VoidCallback onFilter;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final countText = Text(
      '$count ${count == 1 ? 'Product' : 'Products'} Found',
      key: const ValueKey('listing-count'),
      style: TextStyle(
        color: isDark ? Colors.white : _ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
    Widget filterButton({bool expand = false}) => Stack(
      clipBehavior: Clip.none,
      children: [
        _OutlineAction(
          key: const ValueKey('listing-filter'),
          icon: Icons.filter_list_rounded,
          label: 'Filter',
          onTap: onFilter,
          isDark: isDark,
          expand: expand,
        ),
        if (activeFilters > 0)
          Positioned(
            top: -7,
            right: -7,
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _blue,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                '$activeFilters',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ViewToggle(
          isGrid: isGridView,
          onChanged: onViewChanged,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        _OutlineAction(
          key: const ValueKey('listing-sort'),
          icon: Icons.swap_vert_rounded,
          label: sortLabel,
          trailing: Icons.keyboard_arrow_down_rounded,
          onTap: onSort,
          isDark: isDark,
        ),
        const SizedBox(width: 12),
        filterButton(),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              countText,
              const SizedBox(height: 12),
              Row(
                children: [
                  _ViewToggle(
                    isGrid: isGridView,
                    onChanged: onViewChanged,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _OutlineAction(
                      key: const ValueKey('listing-sort'),
                      icon: Icons.swap_vert_rounded,
                      label: sortLabel,
                      onTap: onSort,
                      isDark: isDark,
                      expand: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: filterButton(expand: true)),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: countText),
            controls,
          ],
        );
      },
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.isGrid,
    required this.onChanged,
    required this.isDark,
  });

  final bool isGrid;
  final ValueChanged<bool> onChanged;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    Widget seg(bool grid, IconData icon, String tip) {
      final on = grid == isGrid;
      return Tooltip(
        message: tip,
        child: InkWell(
          key: ValueKey(grid ? 'view-grid' : 'view-list'),
          onTap: on ? null : () => onChanged(grid),
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 52,
            height: 44,
            decoration: BoxDecoration(
              color: on ? _blue : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 22,
              color: on ? Colors.white : (isDark ? Colors.white70 : _navy),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF132233) : const Color(0xFFEAF1F9),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(true, Icons.grid_view_rounded, 'Grid view'),
          seg(false, Icons.view_list_rounded, 'List view'),
        ],
      ),
    );
  }
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.trailing,
    this.expand = false,
  });

  /// Fill the available width and shrink the content to fit.
  final bool expand;
  final IconData icon;
  final String label;
  final IconData? trailing;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : _navy;
    return Material(
      color: isDark ? const Color(0xFF132233) : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? const Color(0xFF1E2D3D) : _line),
          ),
          alignment: expand ? Alignment.center : null,
          child: expand
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 20, color: fg),
                      const SizedBox(width: 10),
                      Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 8),
                        Icon(trailing, size: 20, color: fg),
                      ],
                    ],
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      Icon(trailing, size: 20, color: fg),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Number of active filters shown on the Filter button badge.
int activeFilterCount(ProductFilterState s) =>
    (s.selectedCategoryId != null ? 1 : 0) +
    (s.inStockOnly ? 1 : 0) +
    s.selectedBrands.length +
    ((s.minPrice > 0 || s.maxPrice < 30000) ? 1 : 0);
