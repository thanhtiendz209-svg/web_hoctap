import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'canvas.dart';
import 'model.dart';

typedef PenSettingsChanged =
    void Function(PenKind kind, {Color? color, double? width, bool? dashed});

String penLabel(PenKind kind) => switch (kind) {
  PenKind.ballpoint => 'Bút bi',
  PenKind.fountain => 'Bút mực',
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
      case PenKind.fountain:
        final nib = Path()
          ..moveTo(-4.5, -4.2)
          ..lineTo(4.5, -4.2)
          ..lineTo(4.6, 2.2)
          ..lineTo(0, 11.7)
          ..lineTo(-4.6, 2.2)
          ..close();
        canvas
          ..drawRRect(RRect.fromLTRBXY(-3.1, -10.8, 3.1, -4.2, 1.2, 1.2), edge)
          ..drawPath(nib, fill..color = color.withValues(alpha: 0.24))
          ..drawPath(nib, edge)
          ..drawLine(const Offset(0, 10.5), const Offset(0, 2.5), edge)
          ..drawCircle(const Offset(0, 1.2), 1.35, edge);
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
    this.trigger,
    this.selected = false,
    this.onOpen,
  });

  final String label;
  final Widget panel;
  final IconData icon;
  final bool compact;
  final Widget? trigger;
  final bool selected;
  final VoidCallback? onOpen;

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
      alignmentOffset: Offset(trigger == null && compact ? -31 : 0, 5),
      onOpen: onOpen,
      menuChildren: [panel],
      builder: (context, controller, _) => Tooltip(
        message: label,
        child: Semantics(
          button: true,
          expanded: controller.isOpen,
          selected: selected,
          child: InkWell(
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child:
                trigger ??
                SizedBox(
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

class PenOptionsPanel extends StatelessWidget {
  const PenOptionsPanel({
    super.key,
    required this.preset,
    required this.colors,
    required this.colorNames,
    required this.paperColor,
    required this.onChange,
    required this.onCustomColor,
    this.forShape = false,
  });

  final PenPreset preset;
  final List<Color> colors;
  final List<String> colorNames;
  final Color paperColor;
  final PenSettingsChanged onChange;
  final void Function(PenKind kind, Color color) onCustomColor;
  final bool forShape;

  void _change({PenKind? pen, Color? color, double? width, bool? dashed}) {
    onChange(pen ?? preset.kind, color: color, width: width, dashed: dashed);
  }

  @override
  Widget build(BuildContext context) {
    final color = preset.color;
    final width = preset.width;
    final dashed = preset.dashed;
    final scheme = Theme.of(context).colorScheme;
    final kind = preset.kind;
    return SizedBox(
      width: 288,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              forShape ? 'Kiểu nét hình' : 'Tùy chỉnh bút',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (!forShape) ...[
              const SizedBox(height: 7),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final pen in PenKind.values)
                    SizedBox(
                      width: 127,
                      height: 37,
                      child: Semantics(
                        selected: kind == pen,
                        child: TextButton.icon(
                          onPressed: () => _change(pen: pen),
                          icon: ToolNibPreview(
                            pen: pen,
                            color: color,
                            outline: scheme.onSurface,
                          ),
                          label: Text(penLabel(pen)),
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.onSurface,
                            backgroundColor: kind == pen
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerLow,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 7),
            DecoratedBox(
              decoration: BoxDecoration(
                color: paperColor,
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
                for (var index = 0; index < colors.length; index++)
                  InkColorSwatch(
                    color: colors[index],
                    label: colorNames[index],
                    selected: color == colors[index],
                    onTap: () => _change(color: colors[index]),
                  ),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.colorize_outlined, size: 16),
              onPressed: () => onCustomColor(kind, color),
              label: const Text('Màu tùy chỉnh'),
            ),
            ToolWidthSlider(
              label: 'Độ dày',
              value: width,
              min: PenPreset.minimumWidth(kind),
              max: forShape ? 34 : PenPreset.maximumWidth(kind),
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

class InkColorSwatch extends StatelessWidget {
  const InkColorSwatch({
    super.key,
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
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;

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
          divisions: divisions,
          label: '$shown px',
          semanticFormatterCallback: (value) =>
              '$label ${value.toStringAsFixed(1)} px',
          onChanged: (value) => onChanged((value * 10).round() / 10),
        ),
      ],
    );
  }
}

class EraserOptionsPanel extends StatelessWidget {
  const EraserOptionsPanel({
    super.key,
    required this.width,
    required this.onChanged,
  });

  final double width;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chỉnh gôm', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: CustomPaint(
                size: const Size(double.infinity, 84),
                painter: _EraserPreview(
                  width,
                  scheme.surfaceContainerLow,
                  scheme.onSurfaceVariant,
                  scheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 9),
            ToolWidthSlider(
              label: 'Độ rộng gôm',
              value: width,
              min: minEraserWidth,
              max: maxEraserWidth,
              divisions: (maxEraserWidth - minEraserWidth).toInt(),
              onChanged: onChanged,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final (label, size) in [
                  ('Nhỏ', 12.0),
                  ('Vừa', defaultEraserWidth),
                  ('Lớn', 48.0),
                ])
                  ChoiceChip(
                    label: Text(label),
                    tooltip: '${size.toInt()} px',
                    showCheckmark: false,
                    selected: width == size,
                    onSelected: (_) => onChanged(size),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EraserPreview extends CustomPainter {
  const _EraserPreview(this.width, this.background, this.ink, this.outline);

  final double width;
  final Color background;
  final Color ink;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawLine(
      Offset(18, center.dy + 11),
      Offset(size.width - 18, center.dy - 11),
      Paint()
        ..color = ink
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, width / 2, Paint()..color = background);
    canvas.drawCircle(
      center,
      width / 2,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_EraserPreview oldDelegate) =>
      width != oldDelegate.width ||
      background != oldDelegate.background ||
      ink != oldDelegate.ink ||
      outline != oldDelegate.outline;
}

class _StrokePreview extends CustomPainter {
  const _StrokePreview(this.kind, this.color, this.width, this.dashed);

  final PenKind kind;
  final Color color;
  final double width;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = math.max(13.0, width / 2 + 6);
    final span = size.width - inset * 2;
    if (span <= 0) return;
    final amplitude = math.min(11.0, (size.height - width) / 2 - 3);
    InkPoint sample(double t) => InkPoint(
      Offset(
        inset + span * t,
        size.height / 2 - amplitude * math.sin(t * math.pi * 3),
      ),
    );
    final input = InkStrokeInput(sample(0), kind: kind);
    for (var index = 1; index <= 48; index++) {
      input.add(sample(index / 48));
    }
    paintInkStroke(
      canvas,
      InkStroke(
        points: input.points,
        color: color,
        width: width,
        kind: kind,
        dashed: dashed,
      ),
    );
  }

  @override
  bool shouldRepaint(_StrokePreview oldDelegate) =>
      kind != oldDelegate.kind ||
      color != oldDelegate.color ||
      width != oldDelegate.width ||
      dashed != oldDelegate.dashed;
}
