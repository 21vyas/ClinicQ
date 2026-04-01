import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../core/theme/app_theme.dart';
 
/// Primary CTA button with loading state.
class CQButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? backgroundColor;
 
  const CQButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
  });
 
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor ?? AppColors.primary,
          disabledBackgroundColor:
              (backgroundColor ?? AppColors.primary).withOpacity(0.7),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: isLoading
            ? LoadingAnimationWidget.threeArchedCircle(
                color: Colors.white,
                size: 24,
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
 
/// Google sign-in button.
class CQGoogleButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
 
  const CQGoogleButton({
    super.key,
    this.onPressed,
    this.isLoading = false,
  });
 
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.border, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.white,
        ),
        child: isLoading
            ? LoadingAnimationWidget.threeArchedCircle(
                color: AppColors.primary,
                size: 24,
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GoogleIcon(),
                  const SizedBox(width: 10),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
 
class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}
 
class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;
 
    // Simplified Google "G" icon using arcs
    final colors = [
      const Color(0xFF4285F4),
      const Color(0xFFEA4335),
      const Color(0xFFFBBC05),
      const Color(0xFF34A853),
    ];
 
    final paint = Paint()..style = PaintingStyle.stroke;
    paint.strokeWidth = size.width * 0.18;
 
    // Blue
    paint.color = colors[0];
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.82),
      -0.3,
      1.8,
      false,
      paint,
    );
    // Red
    paint.color = colors[1];
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.82),
      1.5,
      1.7,
      false,
      paint,
    );
    // Yellow
    paint.color = colors[2];
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.82),
      3.2,
      1.0,
      false,
      paint,
    );
    // Green
    paint.color = colors[3];
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.82),
      4.2,
      1.4,
      false,
      paint,
    );
  }
 
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
 
// ─────────────────────────────────────────────
// Error banner widget
// ─────────────────────────────────────────────
 
class CQErrorBanner extends StatelessWidget {
  final String message;
 
  const CQErrorBanner({super.key, required this.message});
 
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFCDD2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
 
// ─────────────────────────────────────────────
// Divider with text
// ─────────────────────────────────────────────
 
class CQDivider extends StatelessWidget {
  final String text;
 
  const CQDivider({super.key, this.text = 'or'});
 
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textHint,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}
 