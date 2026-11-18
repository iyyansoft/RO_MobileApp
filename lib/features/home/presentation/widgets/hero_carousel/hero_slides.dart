import 'package:flutter/material.dart';

/// Base the product stands on.
enum HeroPodium {
  /// Glossy blue water podium (deep blue slides).
  blue,

  /// Natural stone slab (fresh green slides).
  stone,

  /// Frosted white podium (light slides).
  glass,
}

/// How many decorative leaves a slide shows.
enum HeroLeaves { none, accent, lush }

/// A short feature shown under the subtitle (icon + two-line label).
@immutable
class HeroFeature {
  const HeroFeature(this.icon, this.label);

  final IconData icon;

  /// May contain '\n' to control the two-line break.
  final String label;
}

/// Content and visual theme of one Home banner slide.
///
/// The copy, product cut-outs and CTA routes are the Home banner's existing
/// marketing content. Live numbers (product count, starting price) are not
/// stored here: they are computed from the loaded catalogue using
/// [categoryKeywords].
@immutable
class HeroSlide {
  const HeroSlide({
    required this.badge,
    required this.badgeIcon,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.route,
    required this.image,
    required this.colors,
    required this.accent,
    required this.dark,
    required this.podium,
    required this.categoryKeywords,
    this.ink = const Color(0xFF0B2E59),
    this.leaves = HeroLeaves.none,
    this.splash = false,
    this.features = const [],
  });

  final String badge;
  final IconData badgeIcon;

  /// Two lines separated by '\n'.
  final String title;
  final String subtitle;
  final String ctaLabel;

  /// go_router location opened by the CTA.
  final String route;

  /// Transparent product cut-out (asset path).
  final String image;

  /// Background gradient, top-left → bottom-right.
  final List<Color> colors;

  /// Highlight colour. Dark slides: first title line and badge. Light slides:
  /// badge and CTA fill.
  final Color accent;

  /// Dark (deep, white text) or light (fresh, [ink] text) slide.
  final bool dark;

  /// Text colour on light slides.
  final Color ink;
  final HeroPodium podium;
  final HeroLeaves leaves;

  /// Water splash droplets around the podium.
  final bool splash;
  final List<HeroFeature> features;

  /// Matched against a product's category id/name to find this slide's
  /// products in the live catalogue.
  final List<String> categoryKeywords;
}

/// The Home banner slides, in display order (exactly six).
const kHeroSlides = <HeroSlide>[
  HeroSlide(
    badge: '100% GENUINE',
    badgeIcon: Icons.verified_rounded,
    title: 'Genuine\nRO Spares',
    subtitle: 'Filters • Membranes • Pumps • Accessories',
    ctaLabel: 'Shop Now',
    route: '/products',
    image: 'assets/images/banners_cutout/spare_parts.png',
    colors: [Color(0xFF0A3D91), Color(0xFF1565C0), Color(0xFF42A5F5)],
    accent: Color(0xFFA5E4FF),
    dark: true,
    podium: HeroPodium.blue,
    leaves: HeroLeaves.accent,
    splash: true,
    categoryKeywords: ['spare', 'part'],
    features: [
      HeroFeature(Icons.verified_user_rounded, 'Original\nProducts'),
      HeroFeature(Icons.local_shipping_rounded, 'Fast\nDelivery'),
      HeroFeature(Icons.sell_rounded, 'Best\nPricing'),
    ],
  ),
  HeroSlide(
    badge: 'BEST SELLER',
    badgeIcon: Icons.workspace_premium_rounded,
    title: 'Neero+ RO\nWater Purifiers',
    subtitle: 'Pure • Safe • Healthy Drinking Water',
    ctaLabel: 'Shop Now',
    route: '/products',
    image: 'assets/images/banners_cutout/ro_system.png',
    colors: [Color(0xFFF4FBFF), Color(0xFFD3ECFF), Color(0xFF9FD3F8)],
    accent: Color(0xFF0B6BCB),
    ink: Color(0xFF0B2E59),
    dark: false,
    podium: HeroPodium.glass,
    leaves: HeroLeaves.accent,
    categoryKeywords: ['system', 'purifier'],
    features: [
      HeroFeature(Icons.layers_rounded, 'Multi-\nStage'),
      HeroFeature(Icons.flare_rounded, 'RO + UV\nPurification'),
      HeroFeature(Icons.build_circle_rounded, 'Low\nMaintenance'),
    ],
  ),
  HeroSlide(
    badge: 'INSTALL ESSENTIALS',
    badgeIcon: Icons.plumbing_rounded,
    title: 'RO Pipes, Tubing\n& Fittings',
    subtitle: 'Connectors & accessories for every installation',
    ctaLabel: 'Shop Fittings',
    route: '/products',
    image: 'assets/images/banners_cutout/tubes.png',
    colors: [Color(0xFF035A70), Color(0xFF0A89A4), Color(0xFF4CC9E0)],
    accent: Color(0xFFB2F5FF),
    dark: true,
    podium: HeroPodium.blue,
    splash: true,
    categoryKeywords: ['pipe', 'tub', 'fitting'],
    features: [
      HeroFeature(Icons.timeline_rounded, 'RO\nTubing'),
      HeroFeature(Icons.hub_rounded, 'Quick\nConnectors'),
      HeroFeature(Icons.handyman_rounded, 'Every\nInstallation'),
    ],
  ),
  HeroSlide(
    badge: '98% TDS REJECTION',
    badgeIcon: Icons.layers_rounded,
    title: 'Premium Filter\nMembranes',
    subtitle: '75 GPD & 100 GPD anti-bacterial membranes',
    ctaLabel: 'Order Spares',
    route: '/products',
    image: 'assets/images/banners_cutout/membrane.png',
    colors: [Color(0xFFF8F5FF), Color(0xFFE4DAFF), Color(0xFFC3B1F6)],
    accent: Color(0xFF6D3FD8),
    ink: Color(0xFF34186E),
    dark: false,
    podium: HeroPodium.glass,
    categoryKeywords: ['membrane'],
    features: [
      HeroFeature(Icons.filter_alt_rounded, '98% TDS\nRejection'),
      HeroFeature(Icons.health_and_safety_rounded, 'Anti-\nBacterial'),
      HeroFeature(Icons.water_drop_rounded, '75 & 100\nGPD'),
    ],
  ),
  HeroSlide(
    badge: 'HEAVY DUTY',
    badgeIcon: Icons.bolt_rounded,
    title: 'High Pressure\nBooster Pumps',
    subtitle: '100–450 GPD motors with pure copper windings',
    ctaLabel: 'Explore Range',
    route: '/products',
    image: 'assets/images/banners_cutout/pumps.png',
    colors: [Color(0xFF0B1F4A), Color(0xFF16407F), Color(0xFF2F72C6)],
    accent: Color(0xFFFFCB7A),
    dark: true,
    podium: HeroPodium.blue,
    splash: true,
    categoryKeywords: ['pump', 'booster'],
    features: [
      HeroFeature(Icons.speed_rounded, '100–450\nGPD'),
      HeroFeature(Icons.bolt_rounded, 'Copper\nWindings'),
      HeroFeature(Icons.construction_rounded, 'Heavy\nDuty'),
    ],
  ),
  HeroSlide(
    badge: 'LONG LASTING',
    badgeIcon: Icons.eco_rounded,
    title: 'Activated\nCarbon Filters',
    subtitle: 'Remove chlorine, odour & organic impurities',
    ctaLabel: 'Shop Now',
    route: '/products',
    image: 'assets/images/banners_cutout/filter.png',
    colors: [Color(0xFFF2FBF1), Color(0xFFD2F0D6), Color(0xFFA3DCB2)],
    accent: Color(0xFF15803D),
    ink: Color(0xFF14532D),
    dark: false,
    podium: HeroPodium.stone,
    leaves: HeroLeaves.lush,
    categoryKeywords: ['filter', 'carbon', 'cartridge'],
    features: [
      HeroFeature(Icons.water_drop_rounded, 'Pure\nWater'),
      HeroFeature(Icons.eco_rounded, 'Better\nTaste'),
      HeroFeature(Icons.health_and_safety_rounded, 'Health\nProtection'),
    ],
  ),
];

/// Looping decoration runs in the app, but not when the platform asks for
/// reduced motion, and not under widget tests (where an endless animation
/// would make `pumpAndSettle` time out).
bool heroShouldAnimate(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context) &&
    WidgetsBinding.instance is WidgetsFlutterBinding;
