import 'dart:math';

import 'package:flutter/material.dart';

class WaveformIndicator extends StatefulWidget {
  final bool active;
  final Color color;

  const WaveformIndicator({
    super.key,
    required this.active,
    this.color = Colors.white,
  });

  @override
  State<WaveformIndicator> createState() => _WaveformIndicatorState();
}

class _WaveformIndicatorState extends State<WaveformIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void didUpdateWidget(covariant WaveformIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
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
      builder: (context, _) {
        return CustomPaint(
          size: const Size(120, 40),
          painter: _WaveformPainter(
            progress: _controller.value,
            color: widget.active
                ? widget.color
                : widget.color.withValues(alpha: 0.3),
            active: widget.active,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool active;

  _WaveformPainter({
    required this.progress,
    required this.color,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    const barCount = 7;
    final barWidth = size.width / (barCount * 2);
    final maxHeight = size.height * 0.8;
    final centerY = size.height / 2;

    for (var i = 0; i < barCount; i++) {
      final x = barWidth + (i * barWidth * 2);
      double height;

      if (active) {
        final phase = (progress * 2 * pi) + (i * pi / 3);
        height = (sin(phase).abs() * 0.6 + 0.2) * maxHeight;
      } else {
        height = 0.15 * maxHeight;
      }

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.active != active;
  }
}
