import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Unique Animated Wing Logo representing travel, flight, and smart bill distribution.
/// Features dual-wing harmonic oscillation, glowing neon aura, and aerodynamic flight trail.
class AnimatedWingLogo extends StatefulWidget {
  final double size;
  final bool isInteractive;
  final String title;
  final String subtitle;
  final bool showText;
  final List<Color>? wingColors;
  final Color? auraColor;

  const AnimatedWingLogo({
    super.key,
    this.size = 120,
    this.isInteractive = true,
    this.title = 'EquiTrip',
    this.subtitle = 'Smart Trip Expense Splitter',
    this.showText = true,
    this.wingColors,
    this.auraColor,
  });

  @override
  State<AnimatedWingLogo> createState() => _AnimatedWingLogoState();
}

class _AnimatedWingLogoState extends State<AnimatedWingLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _wingFlapAnim;
  late Animation<double> _glowAnim;
  late Animation<double> _floatingAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _wingFlapAnim = Tween<double>(begin: -0.15, end: 0.22).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    _glowAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _floatingAnim = Tween<double>(begin: -5.0, end: 5.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutQuad),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatingAnim.value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing Wing Mascot
              SizedBox(
                width: widget.size * 1.5,
                height: widget.size,
                child: CustomPaint(
                  painter: _WingsPainter(
                    flapProgress: _wingFlapAnim.value,
                    glowIntensity: _glowAnim.value,
                    wingColors: widget.wingColors,
                    auraColor: widget.auraColor,
                  ),
                ),
              ),
              if (widget.showText) ...[
                const SizedBox(height: 10),
                // Brand Title with Gradient Shimmer
                ShaderMask(
                  shaderCallback: (bounds) {
                    return const LinearGradient(
                      colors: [
                        Colors.white,
                        Color(0xFFA5B4FC),
                        Color(0xFF38BDF8),
                        Colors.white,
                      ],
                      stops: [0.0, 0.35, 0.7, 1.0],
                    ).createShader(bounds);
                  },
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: widget.size * 0.26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(
                          color: (widget.auraColor ?? const Color(0xFF6366F1))
                              .withValues(alpha: 0.6),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: widget.size * 0.11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WingsPainter extends CustomPainter {
  final double flapProgress;
  final double glowIntensity;
  final List<Color>? wingColors;
  final Color? auraColor;

  _WingsPainter({
    required this.flapProgress,
    required this.glowIntensity,
    this.wingColors,
    this.auraColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 5);

    final primaryAura = auraColor ?? const Color(0xFF6366F1);

    // 1. Ambient Background Neon Glow Aura
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryAura.withValues(alpha: 0.45 * glowIntensity),
          const Color(0xFF06B6D4).withValues(alpha: 0.25 * glowIntensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.48));

    canvas.drawCircle(center, size.width * 0.48, glowPaint);

    // 2. Draw Left Wing (mirrored)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(-1.0, 1.0);
    _drawSingleWing(canvas, size, flapProgress);
    canvas.restore();

    // 3. Draw Right Wing
    canvas.save();
    canvas.translate(center.dx, center.dy);
    _drawSingleWing(canvas, size, flapProgress);
    canvas.restore();

    // 4. Center Aerodynamic Fuselage / Flight Core
    final coreGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.white,
        wingColors != null && wingColors!.isNotEmpty ? wingColors![1] : const Color(0xFF818CF8),
        primaryAura,
      ],
    ).createShader(Rect.fromLTWH(center.dx - 12, center.dy - 20, 24, 40));

    final corePaint = Paint()
      ..shader = coreGradient
      ..style = PaintingStyle.fill;

    final corePath = Path()
      ..moveTo(center.dx, center.dy - 22) // Top nose tip
      ..quadraticBezierTo(center.dx + 9, center.dy - 4, center.dx + 5, center.dy + 16)
      ..lineTo(center.dx, center.dy + 22) // Bottom jet tail
      ..lineTo(center.dx - 5, center.dy + 16)
      ..quadraticBezierTo(center.dx - 9, center.dy - 4, center.dx, center.dy - 22)
      ..close();

    // Core shadow glow
    canvas.drawShadow(corePath, primaryAura, 10.0, true);
    canvas.drawPath(corePath, corePaint);

    // Jet Engine Center Pulse Orb
    final jetPaint = Paint()
      ..color = Color.lerp(
        wingColors != null ? wingColors!.first : const Color(0xFF38BDF8),
        Colors.white,
        glowIntensity,
      )!
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx, center.dy + 18), 3.5, jetPaint);
  }

  void _drawSingleWing(Canvas canvas, Size size, double flap) {
    // Rotation pivot is origin (center.dx, center.dy)
    final wingAngle = flap * 0.6; // Flapping rotation
    canvas.rotate(wingAngle);

    // Primary Feather Wing Path
    final wingPath = Path()
      ..moveTo(6, -6)
      // Top flight arc to main wingtip
      ..cubicTo(size.width * 0.22, -size.height * 0.45, size.width * 0.42, -size.height * 0.35, size.width * 0.52, -size.height * 0.12)
      // Inner feather curves
      ..cubicTo(size.width * 0.44, 0.0, size.width * 0.36, size.height * 0.14, size.width * 0.42, size.height * 0.22)
      ..cubicTo(size.width * 0.30, size.height * 0.18, size.width * 0.22, size.height * 0.24, size.width * 0.26, size.height * 0.32)
      ..cubicTo(size.width * 0.18, size.height * 0.24, size.width * 0.10, size.height * 0.22, 6, 8)
      ..close();

    // Radiant Wing Gradient
    final defaultColors = const [
      Color(0xFF38BDF8), // Cyan wingtip
      Color(0xFF818CF8), // Indigo mid-feather
      Color(0xFF4F46E5), // Deep primary base
      Color(0xFF7C3AED), // Violet accent
    ];

    final colorsToUse = wingColors ?? defaultColors;

    final wingShader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: colorsToUse,
      stops: const [0.0, 0.35, 0.75, 1.0],
    ).createShader(Rect.fromLTWH(0, -size.height * 0.5, size.width * 0.6, size.height));

    final wingPaint = Paint()
      ..shader = wingShader
      ..style = PaintingStyle.fill;

    // Wing edge highlight stroke
    final borderPaint = Paint()
      ..shader = LinearGradient(
        colors: [Colors.white, colorsToUse[0], colorsToUse[1]],
      ).createShader(Rect.fromLTWH(0, -size.height * 0.5, size.width * 0.6, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    canvas.drawShadow(wingPath, (auraColor ?? const Color(0xFF6366F1)).withValues(alpha: 0.6), 12.0, false);
    canvas.drawPath(wingPath, wingPaint);
    canvas.drawPath(wingPath, borderPaint);

    // Inner Accent Feather Feathering (Secondary layered winglet)
    final featherletPath = Path()
      ..moveTo(8, -4)
      ..cubicTo(size.width * 0.18, -size.height * 0.25, size.width * 0.32, -size.height * 0.18, size.width * 0.38, -size.height * 0.02)
      ..cubicTo(size.width * 0.28, size.height * 0.06, size.width * 0.18, size.height * 0.10, 8, 4)
      ..close();

    final featherletPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.8),
          colorsToUse[0].withValues(alpha: 0.3),
        ],
      ).createShader(Rect.fromLTWH(0, -size.height * 0.3, size.width * 0.4, size.height * 0.4))
      ..style = PaintingStyle.fill;

    canvas.drawPath(featherletPath, featherletPaint);
  }

  @override
  bool shouldRepaint(covariant _WingsPainter oldDelegate) {
    return oldDelegate.flapProgress != flapProgress ||
        oldDelegate.glowIntensity != glowIntensity ||
        oldDelegate.wingColors != wingColors ||
        oldDelegate.auraColor != auraColor;
  }
}
