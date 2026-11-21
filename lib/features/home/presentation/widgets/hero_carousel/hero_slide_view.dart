import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hero_backdrop.dart';
import 'hero_slides.dart';

/// Size class of the banner carousel, chosen from the available width.
enum HeroLayout {
  /// Desktop (>= 960 px): two slides side by side.
  large,

  /// Tablet (600–959 px): one wide slide.
  medium,

  /// Phone (< 600 px): one slide.
  compact;

  static HeroLayout forWidth(double width) =>
      width >= 960 ? large : (width >= 600 ? medium : compact);

  /// Slides visible at once.
  int get visibleSlides => this == large ? 2 : 1;

  /// Card height (equal for every slide).
  double get height => switch (this) {
    large => 320,
    medium => 280,
    compact => 240,
  };

  /// Horizontal padding inside a card.
  double get padding => switch (this) {
    large => 44,
    medium => 44,
    compact => 22,
  };

  HeroStage get stage => switch (this) {
    large => const HeroStage(centerX: 0.73, podiumY: 0.80, podiumWidth: 0.42),
    medium => const HeroStage(centerX: 0.74, podiumY: 0.80, podiumWidth: 0.36),
    compact => const HeroStage(centerX: 0.75, podiumY: 0.82, podiumWidth: 0.44),
  };
}

/// Live catalogue figures for a slide's category.
@immutable
class HeroSlideStats {
  const HeroSlideStats({required this.count, required this.fromPrice});

  final int count;

  /// Lowest dealer price in the category (0 when unknown).
  final double fromPrice;
}

/// One banner card: copy on the left, the product on a podium on the right,
/// over a themed water background.
class HeroSlideView extends StatelessWidget {
  const HeroSlideView({
    super.key,
    required this.slide,
    required this.layout,
    required this.loop,
    required this.onCta,
    this.stats,
  });

  final HeroSlide slide;
  final HeroLayout layout;

  /// Shared, slow looping animation for the background and product float.
  final Animation<double> loop;
  final VoidCallback onCta;
  final HeroSlideStats? stats;

  @override
  Widget build(BuildContext context) {
    final stage = layout.stage;
    final compact = layout == HeroLayout.compact;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final podiumW = w * stage.podiumWidth;
        final productW = math.min(w * (compact ? 0.44 : 0.42), h * 0.78);
        final productBottom = h * (1 - stage.podiumY) + podiumW * 0.02;

        return Stack(
          fit: StackFit.expand,
          children: [
            HeroBackdrop(slide: slide, stage: stage, loop: loop),
            // Product resting on the podium.
            Positioned(
              left: w * stage.centerX - productW / 2,
              width: productW,
              top: h * (compact ? 0.12 : 0.08),
              bottom: productBottom,
              child: _FloatingProduct(
                loop: loop,
                child: Image.asset(
                  // Web-sized transparent cut-outs (max 800 px), preloaded
                  // by the carousel so slides never pop in.
                  slide.image,
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.water_drop_rounded,
                    size: 64,
                    color: slide.dark ? Colors.white : slide.accent,
                  ),
                ),
              ),
            ),
            HeroForeground(slide: slide, stage: stage, loop: loop),
            // Copy.
            Positioned(
              left: layout.padding,
              top: compact ? 12 : 16,
              bottom: compact ? 12 : 16,
              width: w * (compact ? 0.54 : 0.53) - layout.padding,
              child: Align(
                alignment: Alignment.centerLeft,
                child: LayoutBuilder(
                  builder: (context, copyBox) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: copyBox.maxWidth,
                      child: _Copy(
                        slide: slide,
                        layout: layout,
                        stats: stats,
                        onCta: onCta,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Copy extends StatelessWidget {
  const _Copy({
    required this.slide,
    required this.layout,
    required this.stats,
    required this.onCta,
  });

  final HeroSlide slide;
  final HeroLayout layout;
  final HeroSlideStats? stats;
  final VoidCallback onCta;

  @override
  Widget build(BuildContext context) {
    final compact = layout == HeroLayout.compact;
    final dark = slide.dark;
    final ink = dark ? Colors.white : slide.ink;
    final body = dark ? Colors.white.withValues(alpha: 0.92) : slide.ink;
    final badgeText = dark ? slide.colors.first : Colors.white;
    final lines = slide.title.split('\n');
    final s = stats;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Badge.
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 11 : 16,
            vertical: compact ? 6 : 8,
          ),
          decoration: BoxDecoration(
            color: slide.accent,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(slide.badgeIcon, size: compact ? 13 : 16, color: badgeText),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  slide.badge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: badgeText,
                    fontSize: compact ? 10.5 : 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        // Title: scales as one block so both lines keep the same size.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: lines.first,
                  style: TextStyle(color: dark ? slide.accent : ink),
                ),
                if (lines.length > 1)
                  TextSpan(text: '\n${lines.skip(1).join(' ')}'),
              ],
            ),
            softWrap: false,
            style: TextStyle(
              color: ink,
              fontSize: compact ? 26 : 44,
              fontWeight: FontWeight.w800,
              height: 1.08,
              letterSpacing: compact ? -0.6 : -1.2,
            ),
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          slide.subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: body,
            fontSize: compact ? 12.5 : 16,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
        ),
        if (slide.features.isNotEmpty) ...[
          SizedBox(height: compact ? 6 : 10),
          Wrap(
            spacing: compact ? 10 : 18,
            runSpacing: compact ? 4 : 6,
            children: [
              for (final f in slide.features)
                _Feature(feature: f, slide: slide, compact: compact),
            ],
          ),
        ],
        if (s != null && s.count > 0 && !compact) ...[
          const SizedBox(height: 8),
          _StatsLine(stats: s, slide: slide),
        ],
        SizedBox(height: compact ? 10 : 12),
        _HeroCta(slide: slide, compact: compact, onTap: onCta),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.feature,
    required this.slide,
    required this.compact,
  });

  final HeroFeature feature;
  final HeroSlide slide;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(feature.icon, size: compact ? 18 : 24, color: slide.accent),
        SizedBox(width: compact ? 4 : 7),
        Text(
          feature.label,
          maxLines: 2,
          style: TextStyle(
            color: slide.dark ? Colors.white : slide.ink,
            fontSize: compact ? 10 : 12.5,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _StatsLine extends StatelessWidget {
  const _StatsLine({required this.stats, required this.slide});

  final HeroSlideStats stats;
  final HeroSlide slide;

  @override
  Widget build(BuildContext context) {
    final color = slide.dark ? Colors.white : slide.ink;
    return Text.rich(
      TextSpan(
        style: TextStyle(
          color: color.withValues(alpha: 0.85),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        children: [
          TextSpan(
            text: '${stats.count} ${stats.count == 1 ? 'product' : 'products'}',
          ),
          if (stats.fromPrice > 0) ...[
            const TextSpan(text: '  ·  from '),
            TextSpan(
              text: '₹${formatIndianAmount(stats.fromPrice)}',
              style: TextStyle(
                color: slide.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 125000 → "1,25,000" (Indian digit grouping, no decimals).
String formatIndianAmount(double value) {
  final digits = value.round().toString();
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Pill CTA: white on deep slides, filled with the accent on light slides.
class _HeroCta extends StatefulWidget {
  const _HeroCta({
    required this.slide,
    required this.compact,
    required this.onTap,
  });

  final HeroSlide slide;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_HeroCta> createState() => _HeroCtaState();
}

class _HeroCtaState extends State<_HeroCta> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final slide = widget.slide;
    final compact = widget.compact;
    final fill = slide.dark ? Colors.white : slide.accent;
    final text = slide.dark ? slide.colors.first : Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: (slide.dark ? Colors.black : slide.accent).withValues(
                alpha: _hover ? 0.32 : 0.22,
              ),
              blurRadius: _hover ? 22 : 14,
              offset: Offset(0, _hover ? 10 : 6),
            ),
          ],
        ),
        child: Material(
          color: fill,
          borderRadius: BorderRadius.circular(40),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(40),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 18 : 28,
                vertical: compact ? 9 : 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      slide.ctaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: text,
                        fontSize: compact ? 14 : 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(width: compact ? 8 : 12),
                  AnimatedSlide(
                    duration: const Duration(milliseconds: 180),
                    offset: Offset(_hover ? 0.25 : 0, 0),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: compact ? 17 : 21,
                      color: text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gentle float driven by the shared loop (no extra ticker per slide).
class _FloatingProduct extends StatelessWidget {
  const _FloatingProduct({required this.loop, required this.child});

  final Animation<double> loop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: loop,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -4 - 4 * math.sin(loop.value * math.pi * 2 * 4)),
        child: child,
      ),
      child: child,
    );
  }
}
