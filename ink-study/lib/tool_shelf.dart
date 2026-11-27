import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'model.dart';

class ToolNibPreview extends StatelessWidget {
  const ToolNibPreview({
    super.key,
    required this.color,
    required this.outline,
    this.pen,
  });

  final Color color;
  final Color outline;

  /// A null pen describes the eraser.
  final PenKind? pen;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size(31, 30),
      painter: _NibPainter(pen, color, outline),
    ),
  );
}

class _NibPainter extends CustomPainter {
  const _NibPainter(this.pen, this.color, this.outline);

  final PenKind? pen;
  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 4.8);
    switch (pen) {
      case PenKind.ballpoint:
        _ballpoint(canvas);
      case PenKind.pencil:
        _pencil(canvas);
      case PenKind.highlighter:
        _highlighter(canvas);
      case null:
        _eraser(canvas);
    }
    canvas.restore();
  }

  Paint get _edge => Paint()
    ..color = outline.withValues(alpha: 0.7)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.9
    ..strokeJoin = StrokeJoin.round;

  Paint _fill(Color fill) => Paint()..color = fill;

  Color _shine(double amount) => Color.lerp(color, Colors.white, amount)!;

  void _ballpoint(Canvas canvas) {
    final barrel = RRect.fromLTRBXY(-4.2, -13, 4.2, 6.4, 2, 2);
    canvas.drawRRect(barrel, _fill(color));
    canvas.drawRRect(barrel, _edge);
    canvas.drawLine(
      const Offset(-2.1, -10.6),
      const Offset(-2.1, 0.2),
      _fill(_shine(0.68))..strokeWidth = 1.5,
    );
    canvas.drawRect(
      const Rect.fromLTRB(-4.1, 2.2, 4.1, 4.1),
      _fill(_shine(0.43)),
    );
    final tip = Path()
      ..moveTo(-3.2, 6.5)
      ..lineTo(-1.3, 10.4)
      ..lineTo(1.3, 10.4)
      ..lineTo(3.2, 6.5)
      ..close();
    canvas.drawPath(tip, _fill(_shine(0.62)));
    canvas.drawPath(tip, _edge);
    canvas.drawLine(
      const Offset(0, 10.6),
      const Offset(0, 13),
      _fill(color)..strokeWidth = 1.6,
    );
  }

  void _pencil(Canvas canvas) {
    const barrel = Rect.fromLTRB(-3.6, -13, 3.6, 6.8);
    canvas.drawRect(barrel, _fill(color));
    canvas.drawRect(
      const Rect.fromLTRB(-1.6, -13, 0.6, 6.8),
      _fill(_shine(0.50)),
    );
    canvas.drawRect(barrel, _edge);
    final wood = Path()
      ..moveTo(-3.6, 6.8)
      ..lineTo(0, 13.1)
      ..lineTo(3.6, 6.8)
      ..close();
    canvas.drawPath(wood, _fill(const Color(0xffe7bf8a)));
    canvas.drawPath(wood, _edge);
    final graphite = Path()
      ..moveTo(-1.3, 10.8)
      ..lineTo(0, 13.1)
      ..lineTo(1.3, 10.8)
      ..close();
    canvas.drawPath(graphite, _fill(color));
  }

  void _highlighter(Canvas canvas) {
    final barrel = RRect.fromLTRBXY(-5.7, -12.4, 5.7, 7, 2, 2);
    canvas.drawRRect(barrel, _fill(_shine(0.23)));
    canvas.drawRRect(barrel, _edge);
    canvas.drawRect(const Rect.fromLTRB(-5.4, 2.5, 5.4, 4.5), _fill(color));
    final tip = Path()
      ..moveTo(-3.9, 7)
      ..lineTo(-3.9, 12.5)
      ..lineTo(3.9, 10)
      ..lineTo(3.9, 7)
      ..close();
    canvas.drawPath(tip, _fill(color));
    canvas.drawPath(tip, _edge);
  }

  void _eraser(Canvas canvas) {
    final casing = RRect.fromLTRBXY(-6.2, -11.5, 6.2, 11.5, 2.5, 2.5);
    canvas.drawRRect(casing, _fill(_shine(0.42)));
    canvas.save();
    canvas.clipRRect(casing);
    canvas.drawRect(const Rect.fromLTRB(-6.2, -11.5, 6.2, 1.5), _fill(color));
    canvas.drawLine(
      const Offset(-6.2, 1.5),
      const Offset(6.2, 1.5),
      _fill(outline.withValues(alpha: 0.45))..strokeWidth = 0.8,
    );
    canvas.restore();
    canvas.drawRRect(casing, _edge);
  }

  @override
  bool shouldRepaint(_NibPainter oldDelegate) =>
      oldDelegate.pen != pen ||
      oldDelegate.color != color ||
      oldDelegate.outline != outline;
}
