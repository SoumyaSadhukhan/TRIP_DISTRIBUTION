import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Interactive Ambient Particle & Glow Mesh Background for immersive travel aesthetics.
class AmbientParticlesBackground extends StatefulWidget {
  final Widget child;
  final int numberOfParticles;
  final bool enableFloatingStars;

  const AmbientParticlesBackground({
    super.key,
    required this.child,
    this.numberOfParticles = 24,
    this.enableFloatingStars = true,
  });

  @override
  State<AmbientParticlesBackground> createState() => _AmbientParticlesBackgroundState();
}

class _AmbientParticlesBackgroundState extends State<AmbientParticlesBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // Generate random ambient star particles
    for (int i = 0; i < widget.numberOfParticles; i++) {
      _particles.add(
        _Particle(
          x: _random.nextDouble(),
          y: _random.nextDouble(),
          radius: _random.nextDouble() * 2.2 + 0.8,
          speed: _random.nextDouble() * 0.15 + 0.05,
          opacity: _random.nextDouble() * 0.6 + 0.2,
          isGlowing: _random.nextBool(),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Deep Midnight Cosmic Gradient
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F172A), // Deep Slate Navy
                  Color(0xFF1E1B4B), // Midnight Indigo
                  Color(0xFF2E1065), // Deep Regal Purple
                  Color(0xFF090D16), // Dark Obsidian
                ],
                stops: [0.0, 0.45, 0.82, 1.0],
              ),
            ),
          ),
        ),

        // 2. Animated Ambient Nebula Orbs
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * 2 * math.pi;
            final orb1X = 0.25 + 0.15 * math.cos(t);
            final orb1Y = 0.20 + 0.12 * math.sin(t);
            final orb2X = 0.75 - 0.18 * math.sin(t * 0.8);
            final orb2Y = 0.70 + 0.14 * math.cos(t * 0.8);

            return CustomPaint(
              size: Size.infinite,
              painter: _NebulaPainter(
                orb1: Offset(orb1X, orb1Y),
                orb2: Offset(orb2X, orb2Y),
                particles: _particles,
                time: _controller.value,
              ),
            );
          },
        ),

        // 3. Child Screen Content
        widget.child,
      ],
    );
  }
}

class _Particle {
  double x;
  double y;
  final double radius;
  final double speed;
  final double opacity;
  final bool isGlowing;

  _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.opacity,
    required this.isGlowing,
  });
}

class _NebulaPainter extends CustomPainter {
  final Offset orb1;
  final Offset orb2;
  final List<_Particle> particles;
  final double time;

  _NebulaPainter({
    required this.orb1,
    required this.orb2,
    required this.particles,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Top-left Violet Glow Nebula
    final p1 = Offset(orb1.dx * size.width, orb1.dy * size.height);
    final paint1 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF6366F1).withValues(alpha: 0.28),
          const Color(0xFF4338CA).withValues(alpha: 0.12),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: p1, radius: size.width * 0.55));
    canvas.drawCircle(p1, size.width * 0.55, paint1);

    // Bottom-right Cyan / Turquoise Glow Nebula
    final p2 = Offset(orb2.dx * size.width, orb2.dy * size.height);
    final paint2 = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF06B6D4).withValues(alpha: 0.22),
          const Color(0xFF3B82F6).withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: p2, radius: size.width * 0.60));
    canvas.drawCircle(p2, size.width * 0.60, paint2);

    // Draw Floating Starlight Particles
    for (final pt in particles) {
      final currentY = (pt.y - time * pt.speed) % 1.0;
      final offset = Offset(pt.x * size.width, currentY * size.height);

      final pulse = 0.5 + 0.5 * math.sin((time * 2 * math.pi) + (pt.x * 10));
      final alpha = (pt.opacity * (0.6 + 0.4 * pulse)).clamp(0.0, 1.0);

      final starPaint = Paint()
        ..color = (pt.isGlowing ? const Color(0xFF93C5FD) : Colors.white).withValues(alpha: alpha);

      canvas.drawCircle(offset, pt.radius, starPaint);

      if (pt.isGlowing && pt.radius > 1.8) {
        final aura = Paint()
          ..color = const Color(0xFF38BDF8).withValues(alpha: alpha * 0.35);
        canvas.drawCircle(offset, pt.radius * 2.8, aura);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NebulaPainter oldDelegate) => true;
}
