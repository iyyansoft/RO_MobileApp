import 'dart:async';

import 'package:flutter/material.dart';

/// Compact toast notifications used across the app (e.g. "Product added to
/// cart successfully").
///
/// * Desktop (>= 1024 px): a small card at the bottom-right.
/// * Mobile/tablet: a compact card near the bottom, above the bottom
///   navigation bar and the product page's Add to Cart / Buy Now bar.
/// * White card, subtle shadow, rounded corners; green check for success,
///   red icon for errors; optional small action (e.g. "View Cart").
/// * Slides up and fades in; fades out; auto-dismisses after 3 s.
/// * One toast at a time: showing the same message again just restarts its
///   timer (no duplicates); a different message replaces it.
class AppToast {
  AppToast._();

  static const displayDuration = Duration(seconds: 3);

  static _ToastHandle? _current;

  /// Success toast with a green check.
  static void success(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) => _show(
    context,
    message,
    error: false,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  /// Compact error toast.
  static void error(BuildContext context, String message) =>
      _show(context, message, error: true);

  /// Removes the current toast immediately (e.g. before navigating away).
  static void hide() {
    _current?.remove();
    _current = null;
  }

  static void _show(
    BuildContext context,
    String message, {
    required bool error,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    // Same toast already showing: keep it and restart the timer.
    final current = _current;
    if (current != null &&
        current.message == message &&
        current.error == error &&
        !current.closing) {
      current.restartTimer();
      return;
    }
    hide();
    final handle = _ToastHandle(message: message, error: error);
    handle.entry = OverlayEntry(
      builder: (context) => _ToastView(
        key: handle.viewKey,
        message: message,
        error: error,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                hide();
                onAction();
              },
        onClose: () {
          if (identical(_current, handle)) _current = null;
          handle.entry?.remove();
          handle.entry = null;
        },
      ),
    );
    _current = handle;
    overlay.insert(handle.entry!);
  }
}

class _ToastHandle {
  _ToastHandle({required this.message, required this.error});

  final String message;
  final bool error;
  final viewKey = GlobalKey<_ToastViewState>();
  OverlayEntry? entry;
  bool closing = false;

  /// Restarts the auto-dismiss timer (it lives in the toast widget, so it
  /// is cancelled whenever the toast is removed).
  void restartTimer() => viewKey.currentState?.restartTimer();

  void remove() {
    closing = true;
    entry?.remove();
    entry = null;
  }
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    super.key,
    required this.message,
    required this.error,
    required this.onClose,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onClose;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  )..forward();

  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.6),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));

  Timer? _timer;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    restartTimer();
  }

  void restartTimer() {
    _timer?.cancel();
    _timer = Timer(AppToast.displayDuration, close);
  }

  /// Fades out, then removes the toast.
  Future<void> close() async {
    _timer?.cancel();
    if (!mounted || _closing) return;
    _closing = true;
    await _anim.reverse();
    if (mounted) widget.onClose();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final desktop = width >= 1024;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.error
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);

    final card = Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16263A) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.error
                    ? Icons.error_outline_rounded
                    : Icons.check_rounded,
                size: 17,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.message,
                key: const ValueKey('app-toast-message'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            if (widget.actionLabel != null && widget.onAction != null)
              TextButton(
                key: const ValueKey('app-toast-action'),
                onPressed: widget.onAction,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0B63F6),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 34),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: Text(widget.actionLabel!),
              )
            else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );

    final animated = FadeTransition(
      opacity: _anim,
      child: SlideTransition(position: _slide, child: card),
    );

    // Desktop: bottom-right. Mobile: above the bottom bar(s).
    return desktop
        ? Positioned(right: 24, bottom: 24, width: 380, child: animated)
        : Positioned(
            left: 16,
            right: 16,
            bottom: media.padding.bottom + 96,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: animated,
              ),
            ),
          );
  }
}
