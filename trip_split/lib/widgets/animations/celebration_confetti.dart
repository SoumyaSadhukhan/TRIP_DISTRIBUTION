import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Celebratory Confetti & Golden Wing particles for debt settlement milestones.
class CelebrationConfetti extends StatefulWidget {
  final Widget child;
  final bool isTriggered;

  const CelebrationConfetti({
    super.key,
    required this.child,
    required this.isTriggered,
  });

  @override
  State<CelebrationConfetti> createState() => _CelebrationConfettiState();
}

class _CelebrationConfettiState extends State<CelebrationConfetti>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ConfettiPiece> _pieces = [];
  final math.Random _random = math.Random();

  final List<Color> _colors = const [
    Color(0xFFF59E0B), // Gold
    Color(0xFF10B981), // Emerald
    Color(0xFF6366F1), // Indigo
    Color(0xFFEC4899), // Pink
    Color(0xFF06B6D4), // Cyan
    Color(0xFFFBBF24), // Amber
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    if (widget.isTriggered) {
      _startCelebration();
    }
  }

  @override
  void didUpdateWidget(covariant CelebrationConfetti oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isTriggered && widget.isTriggered) {
      _startCelebration();
    }
  }

  void _startCelebration() {
    _pieces.clear();
    for (int i = 0; i < 60; i++) {
      _pieces.add(
        _ConfettiPiece(
          x: 0.5 + (_random.nextDouble() - 0.5) * 0.2,
          y: 0.35,
          vx: (_random.nextDouble() - 0.5) * 1.8,
          vy: -(_random.nextDouble() * 1.2 + 0.8),
          color: _colors[_random.nextInt(_colors.length)],
          size: _random.nextDouble() * 8.0 + 4.0,
          rotation: _random.nextDouble() * 2 * math.pi,
          rotationSpeed: (_random.nextDouble() - 0.5) * 8.0,
        ),
      );
    }
    _controller.forward(from: 0.0);
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
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (!_controller.isAnimating && _controller.isCompleted) {
              return const SizedBox.shrink();
            }
            return IgnorePointer(
              child: CustomPaint(
                size: Size.infinite,
                painter: _ConfettiPainter(
                  pieces: _pieces,
                  progress: _controller.value,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ConfettiPiece {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final Color color;
  final double size;
  final double rotation;
  final double rotationSpeed;

  _ConfettiPiece({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiPiece> pieces;
  final double progress;

  _ConfettiPainter({required this.pieces, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final gravity = 2.4 * progress * progress;

    for (final p in pieces) {
      final currentX = (p.x + p.vx * progress) * size.width;
      final currentY = (p.y + p.vy * progress + gravity) * size.height;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      final paint = Paint()
        ..color = p.color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(p.rotation + p.rotationSpeed * progress);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
