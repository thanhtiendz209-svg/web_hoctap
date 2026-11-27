import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'model.dart';

typedef PenSettings = (Color, double, bool);
typedef PenSettingsChanged =
    void Function(PenKind kind, {Color? color, double? width, bool? dashed});

String penLabel(PenKind kind) => switch (kind) {
  PenKind.ballpoint => 'Bút bi',
  PenKind.pencil => 'Bút chì',
  PenKind.highlighter => 'Dạ quang',
};

class ToolNibPreview extends StatelessWidget {
  const ToolNibPreview({
    super.key,
    required this.color,
    required this.outline,
    this.pen,
  });

  final Color color;
  final Color outline;

  /// A null pen displays the eraser.
  final PenKind? pen;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: const Size(27, 28),
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
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..rotate(math.pi / 4);
    final edge = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;
    switch (pen) {
      case PenKind.ballpoint:
        final grip = Path()
          ..moveTo(-3.5, 4.5)
          ..lineTo(0, 11.3)
          ..lineTo(3.5, 4.5)
          ..close();
        canvas
          ..drawRRect(RRect.fromLTRBXY(-3.5, -10.7, 3.5, 4.5, 2, 2), edge)
          ..drawLine(const Offset(-3, -6), const Offset(3, -6), edge)
          ..drawPath(grip, fill)
          ..drawPath(grip, edge);
      case PenKind.pencil:
        final body = Path()
          ..moveTo(-3.3, -10)
          ..lineTo(3.3, -10)
          ..lineTo(3.3, 5.2)
          ..lineTo(0, 11.1)
          ..lineTo(-3.3, 5.2)
          ..close();
        final nib = Path()
          ..moveTo(-2, 7.5)
          ..lineTo(2, 7.5)
          ..lineTo(0, 11.1)
          ..close();
        canvas
          ..drawPath(nib, fill)
          ..drawPath(body, edge)
          ..drawLine(const Offset(0, -10), const Offset(0, 4.6), edge);
      case PenKind.highlighter:
        final tip = Path()
          ..moveTo(-3, 5.2)
          ..lineTo(3, 5.2)
          ..lineTo(3, 8.4)
          ..lineTo(-3, 11.4)
          ..close();
        canvas
          ..drawRRect(RRect.fromLTRBXY(-4.8, -9.8, 4.8, 5.2, 2.5, 2.5), edge)
          ..drawLine(const Offset(-4, -5.4), const Offset(4, -5.4), edge)
          ..drawPath(tip, fill)
          ..drawPath(tip, edge);
      case null:
        final casing = RRect.fromLTRBXY(-5, -9.5, 5, 9.5, 2.3, 2.3);
        canvas
          ..drawRRect(casing, fill..color = color.withValues(alpha: 0.14))
          ..drawRRect(casing, edge)
          ..drawLine(const Offset(-4.4, 2), const Offset(4.4, 2), edge);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NibPainter oldDelegate) =>
      oldDelegate.pen != pen ||
      oldDelegate.color != color ||
      oldDelegate.outline != outline;
}

/// Shared anchoring and surface treatment for in-context ribbon controls.
class ToolOptionsMenu extends StatelessWidget {
  const ToolOptionsMenu({
    super.key,
    required this.label,
    required this.panel,
    this.icon = Icons.keyboard_arrow_down_rounded,
    this.compact = true,
  });

  final String label;
  final Widget panel;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(scheme.surface),
        shadowColor: WidgetStatePropertyAll(
          scheme.shadow.withValues(alpha: 0.28),
        ),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
      alignmentOffset: Offset(compact ? -31 : 0, 5),
      menuChildren: [panel],
      builder: (context, controller, _) => Tooltip(
        message: label,
        child: Semantics(
          button: true,
          expanded: controller.isOpen,
          child: InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: SizedBox(
              width: compact ? 20 : 35,
              height: 36,
              child: Icon(icon, size: compact ? 15 : 18),
            ),
          ),
        ),
      ),
    );
  }
}

class PenOptionsPanel extends StatefulWidget {
  const PenOptionsPanel({
    super.key,
    required this.pen,
    required this.presets,
    required this.colors,
    required this.colorNames,
    required this.paperColor,
    required this.onChange,
    required this.onCustomColor,
    this.forShape = false,
  });

  final PenKind pen;
  final Map<PenKind, PenSettings> presets;
  final List<Color> colors;
  final List<String> colorNames;
  final Color paperColor;
  final PenSettingsChanged onChange;
  final void Function(PenKind kind, Color color) onCustomColor;
  final bool forShape;

  @override
  State<PenOptionsPanel> createState() => _PenOptionsPanelState();
}

class _PenOptionsPanelState extends State<PenOptionsPanel> {
  late PenKind _pen = widget.pen;

  void _change({PenKind? pen, Color? color, double? width, bool? dashed}) {
    setState(() => _pen = pen ?? _pen);
    widget.onChange(_pen, color: color, width: width, dashed: dashed);
  }

  @override
  Widget build(BuildContext context) {
    final (color, width, dashed) = widget.presets[_pen]!;
    final scheme = Theme.of(context).colorScheme;
    final kind = widget.forShape ? PenKind.ballpoint : _pen;
    return SizedBox(
      width: 288,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.forShape ? 'Kiểu nét hình' : 'Tùy chỉnh bút',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (!widget.forShape) ...[
              const SizedBox(height: 7),
              Wrap(
                spacing: 5,
                children: [
                  for (final pen in PenKind.values)
                    ChoiceChip(
                      label: Text(penLabel(pen)),
                      selected: _pen == pen,
                      showCheckmark: false,
                      onSelected: (_) => _change(pen: pen),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 7),
            DecoratedBox(
              decoration: BoxDecoration(
                color: widget.paperColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Semantics(
                label: 'Xem trước nét',
                child: CustomPaint(
                  size: const Size(double.infinity, 53),
                  painter: _StrokePreview(kind, color, width, dashed),
                ),
              ),
            ),
            const SizedBox(height: 11),
            Text('Màu nét', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 5,
              children: [
                for (var index = 0; index < widget.colors.length; index++)
                  _ColorSwatch(
                    color: widget.colors[index],
                    label: widget.colorNames[index],
                    selected: color == widget.colors[index],
                    onTap: () => _change(color: widget.colors[index]),
                  ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.colorize_outlined, size: 16),
              onPressed: () => widget.onCustomColor(_pen, color),
              label: const Text('Màu tùy chỉnh'),
            ),
            ToolWidthSlider(
              label: 'Độ dày',
              value: width,
              min: kind == PenKind.highlighter ? 4 : 0.8,
              max: kind == PenKind.highlighter || widget.forShape ? 34 : 14,
              onChanged: (value) => _change(width: value),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final pattern in [false, true])
                  ChoiceChip(
                    label: Text(pattern ? 'Nét đứt' : 'Nét liền'),
                    selected: dashed == pattern,
                    showCheckmark: false,
                    onSelected: (_) => _change(dashed: pattern),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        child: InkResponse(
          onTap: onTap,
          radius: 14,
          child: Container(
            width: 27,
            height: 27,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.42),
                ),
              ),
              child: selected
                  ? Icon(
                      Icons.check_rounded,
                      size: 14,
                      color:
                          ThemeData.estimateBrightnessForColor(color) ==
                              Brightness.dark
                          ? Colors.white
                          : const Color(0xff15253e),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class ToolWidthSlider extends StatelessWidget {
  const ToolWidthSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text('$shown px'),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          label: '$shown px',
          semanticFormatterCallback: (value) =>
              '$label ${value.toStringAsFixed(1)} px',
          onChanged: (value) => onChanged((value * 10).round() / 10),
        ),
      ],
    );
  }
}

class _StrokePreview extends CustomPainter {
  const _StrokePreview(this.kind, this.color, this.width, this.dashed);

  final PenKind kind;
  final Color color;
  final double width;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(
        alpha: switch (kind) {
          PenKind.ballpoint => 1,
          PenKind.pencil => 0.78,
          PenKind.highlighter => 0.32,
        },
      )
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;
    final inset = math.max(13.0, width / 2 + 6);
    final span = size.width - inset * 2;
    if (span <= 0) return;
    final center = size.height / 2;
    final stroke = Path()
      ..moveTo(inset, center + 4)
      ..cubicTo(
        inset + span * 0.20,
        center - 12,
        inset + span * 0.32,
        center + 11,
        inset + span * 0.49,
        center + 2,
      )
      ..cubicTo(
        inset + span * 0.66,
        center - 11,
        inset + span * 0.75,
        center + 12,
        size.width - inset,
        center - 3,
      );
    if (!dashed) {
      canvas.drawPath(stroke, paint);
      return;
    }
    final dash = math.max(5.0, width * 3);
    final cycle = dash + math.max(3.0, width * 2);
    final metric = stroke.computeMetrics().first;
    for (var offset = 0.0; offset < metric.length; offset += cycle) {
      canvas.drawPath(
        metric.extractPath(offset, math.min(offset + dash, metric.length)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StrokePreview oldDelegate) =>
      kind != oldDelegate.kind ||
      color != oldDelegate.color ||
      width != oldDelegate.width ||
      dashed != oldDelegate.dashed;
}
