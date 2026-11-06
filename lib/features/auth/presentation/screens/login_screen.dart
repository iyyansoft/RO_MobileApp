import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../providers/auth_provider.dart';

class _LoginBackgroundPainter extends CustomPainter {
  final bool isDark;
  const _LoginBackgroundPainter({this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    if (isDark) {
      // Soft dark ambient glow in dark mode
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFF0369A1).withValues(alpha: 0.16),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(
          center: Offset(w * 0.15, h * 0.20),
          radius: w * 0.35,
        ));
      canvas.drawCircle(Offset(w * 0.15, h * 0.20), w * 0.35, glowPaint);
      return;
    }

    // 1. Top-left soft sky-blue ambient orb
    final orb1 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFBAE6FD).withValues(alpha: 0.50),
          const Color(0xFFE0F2FE).withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.12, h * 0.16),
        radius: w * 0.40,
      ));
    canvas.drawCircle(Offset(w * 0.12, h * 0.16), w * 0.40, orb1);

    // 2. Bottom-right soft teal-blue ambient orb
    final orb2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFC7F2EE).withValues(alpha: 0.45),
          const Color(0xFFE0F7FA).withValues(alpha: 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.60, 1.0],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.88, h * 0.84),
        radius: w * 0.44,
      ));
    canvas.drawCircle(Offset(w * 0.88, h * 0.84), w * 0.44, orb2);

    // 3. Center-right delicate water flow curve
    final curvePath = Path()
      ..moveTo(w * 0.70, 0)
      ..cubicTo(w * 0.95, h * 0.30, w * 0.65, h * 0.70, w, h * 0.85)
      ..lineTo(w, 0)
      ..close();
    final curvePaint = Paint()..color = const Color(0x180284C7);
    canvas.drawPath(curvePath, curvePaint);

    // 4. Subtle floating water bubble accents
    final bubbleFill = Paint()..color = const Color(0x280284C7);
    final bubbleStroke = Paint()
      ..color = const Color(0x4438BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final bubbleHighlight = Paint()..color = Colors.white.withValues(alpha: 0.70);

    final bubbles = [
      (0.16, 0.76, 14.0),
      (0.22, 0.82, 8.0),
      (0.82, 0.22, 16.0),
      (0.88, 0.28, 9.0),
      (0.08, 0.38, 11.0),
      (0.92, 0.62, 13.0),
    ];

    for (final (bx, by, r) in bubbles) {
      final center = Offset(w * bx, h * by);
      canvas.drawCircle(center, r, bubbleFill);
      canvas.drawCircle(center, r, bubbleStroke);
      canvas.drawCircle(
        Offset(center.dx - r * 0.35, center.dy - r * 0.35),
        r * 0.30,
        bubbleHighlight,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LoginBackgroundPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.usePassword = false});
  final bool usePassword;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _usePassword = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _usePassword = widget.usePassword;
    if (_usePassword) {
      _email.text = ref.read(authProvider).email;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!_form.currentState!.validate()) return;
    final success = _usePassword
        ? await ref
              .read(authProvider.notifier)
              .loginWithPassword(_email.text, _password.text)
        : await ref.read(authProvider.notifier).sendOtp(_email.text);
    if (success && mounted) {
      context.go(_usePassword ? '/home' : '/otp');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 600;

    final primaryColor = isDark
        ? AppColors.accentDark
        : AppColors.primaryLight;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF1E2D3D)
        : const Color(0xFFE2E8F0);

    return Scaffold(
      body: Stack(
        children: [
          // 1. Light Blue Gradient Background with Soft Decorative Water Shapes
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? const [
                          Color(0xFF09111A),
                          Color(0xFF0D1B2A),
                          Color(0xFF0A1420),
                        ]
                      : const [
                          Color(0xFFE8F4FD),
                          Color(0xFFF1F8FE),
                          Color(0xFFF8FCFF),
                        ],
                ),
              ),
              child: CustomPaint(
                painter: _LoginBackgroundPainter(isDark: isDark),
              ),
            ),
          ),

          // 2. Properly Centered White Login Card
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 16 : 24,
                  vertical: isMobile ? 24 : 36,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 24 : 40,
                      vertical: isMobile ? 28 : 38,
                    ),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderColor, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F4C81).withValues(
                            alpha: isDark ? 0.35 : 0.08,
                          ),
                          blurRadius: 36,
                          offset: const Offset(0, 14),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.20 : 0.03,
                          ),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildForm(
                      context,
                      auth: auth,
                      isDark: isDark,
                      primaryColor: primaryColor,
                      isMobile: isMobile,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(
    BuildContext context, {
    required AuthState auth,
    required bool isDark,
    required Color primaryColor,
    required bool isMobile,
  }) {
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Neero Brand Logo at Top
          const Center(
            child: BrandLogo(
              width: 170,
              height: 50,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 24),

          // 2. Heading & Subtitle
          const Text(
            'Welcome Back',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _usePassword
                ? 'Sign in to your wholesale account with your password.'
                : 'Enter your email address to receive a 6-digit sign-in code.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: isDark ? Colors.white60 : const Color(0xFF64748B),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),

          // 3. Mode Switcher Pill (Password vs OTP)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E2D3D)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _usePassword = true),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _usePassword
                            ? (isDark
                                  ? const Color(0xFF2B3E52)
                                  : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: _usePassword
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        'Sign in with password',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _usePassword
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: _usePassword
                              ? primaryColor
                              : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _usePassword = false),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: !_usePassword
                            ? (isDark
                                  ? const Color(0xFF2B3E52)
                                  : Colors.white)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: !_usePassword
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Text(
                        'Sign in with code (OTP)',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: !_usePassword
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: !_usePassword
                              ? primaryColor
                              : (isDark ? Colors.white60 : Colors.black54),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Email or Mobile Input
          TextFormField(
            controller: _email,
            keyboardType: _usePassword
                ? TextInputType.text
                : TextInputType.emailAddress,
            textInputAction: _usePassword
                ? TextInputAction.next
                : TextInputAction.done,
            autofillHints: _usePassword
                ? const [AutofillHints.username]
                : const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: _usePassword
                  ? 'Email or mobile number'
                  : 'Email address',
              hintText: _usePassword
                  ? 'e.g. dealer@example.com or 9876543210'
                  : 'e.g. dealer@example.com',
              prefixIcon: Icon(
                _usePassword
                    ? Icons.person_outline_rounded
                    : Icons.email_outlined,
                color: primaryColor,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            validator: (value) {
              final input = value?.trim() ?? '';
              final validEmail = RegExp(
                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
              ).hasMatch(input);
              final validMobile = RegExp(r'^\d{10}$').hasMatch(input);
              return validEmail || (_usePassword && validMobile)
                  ? null
                  : _usePassword
                  ? 'Enter a valid email or 10-digit mobile number'
                  : 'Enter a valid email address';
            },
            onFieldSubmitted: (_) => _usePassword ? null : _sendCode(),
          ),

          // 5. Password Field (When in password mode)
          if (_usePassword) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Password',
                hintText: 'Enter your account password',
                prefixIcon: Icon(
                  Icons.lock_outline_rounded,
                  color: primaryColor,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.grey,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
              validator: (value) =>
                  (value ?? '').isEmpty ? 'Enter password' : null,
              onFieldSubmitted: (_) => _sendCode(),
            ),
          ],

          // 6. Error Message Alert
          if (auth.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        auth.errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFEF4444),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 22),

          // 7. Main Submit Button
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: auth.isLoading ? null : _sendCode,
              style: FilledButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: auth.isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      _usePassword ? 'Sign in' : 'Send sign in code',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 16),

          // 8. Navigation Links (Create Account & Forgot Password)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              TextButton(
                onPressed: () => context.push('/register'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Create a dealer account',
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push('/forgot-password'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // 9. Shop Employee Login Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/shop/login'),
              icon: const Icon(Icons.storefront_outlined, size: 20),
              label: const Text(
                'Shop Employee Login',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: isDark
                      ? const Color(0xFF203A5A)
                      : const Color(0xFFCBD5E1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
