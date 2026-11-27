import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Client-area buttons for the Windows title bar.
class InkWindowControls extends StatefulWidget {
  const InkWindowControls({super.key});

  @override
  State<InkWindowControls> createState() => _InkWindowControlsState();
}

class _InkWindowControlsState extends State<InkWindowControls>
    with WindowListener {
  late final bool _available;
  bool _maximized = false;
  bool _fullscreen = false;
  int _readVersion = 0;

  @override
  void initState() {
    super.initState();
    _available = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    if (_available) {
      windowManager.addListener(this);
      _refresh();
    }
  }

  @override
  void dispose() {
    if (_available) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _invoke(Future<void> Function() action) async {
    try {
      await action();
    } on MissingPluginException {
      // The platform plugin is absent in widget tests.
    }
  }

  void _refresh() {
    final version = ++_readVersion;
    unawaited(
      _invoke(() async {
        final maximized = await windowManager.isMaximized();
        final fullscreen = await windowManager.isFullScreen();
        if (!mounted || version != _readVersion) return;
        if (_maximized == maximized && _fullscreen == fullscreen) return;
        setState(() {
          _maximized = maximized;
          _fullscreen = fullscreen;
        });
      }),
    );
  }

  @override
  void onWindowMaximize() => _refresh();

  @override
  void onWindowUnmaximize() => _refresh();

  @override
  void onWindowRestore() => _refresh();

  @override
  void onWindowEnterFullScreen() => _refresh();

  @override
  void onWindowLeaveFullScreen() => _refresh();

  Future<void> _resize() async {
    if (await windowManager.isFullScreen()) {
      await windowManager.setFullScreen(false);
    } else if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final resizeIcon = _fullscreen
        ? Icons.fullscreen_exit_rounded
        : _maximized
        ? Icons.filter_none_rounded
        : Icons.crop_square_rounded;
    final resizeLabel = _fullscreen
        ? 'Thoát toàn màn hình'
        : _maximized
        ? 'Khôi phục cửa sổ'
        : 'Phóng to cửa sổ';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          label: 'Thu nhỏ cửa sổ',
          icon: Icons.horizontal_rule_rounded,
          onPressed: () => unawaited(_invoke(windowManager.minimize)),
        ),
        _WindowButton(
          label: resizeLabel,
          icon: resizeIcon,
          onPressed: () => unawaited(_invoke(_resize)),
        ),
        _WindowButton(
          label: 'Đóng cửa sổ',
          icon: Icons.close_rounded,
          danger: true,
          onPressed: () => unawaited(_invoke(windowManager.close)),
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    bool highlighted(Set<WidgetState> states) =>
        states.contains(WidgetState.hovered) ||
        states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.focused);

    return SizedBox(
      width: 42,
      height: 40,
      child: IconButton(
        tooltip: label,
        icon: Icon(icon, size: 17),
        onPressed: onPressed,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          visualDensity: VisualDensity.standard,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(6)),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (!highlighted(states)) return Colors.transparent;
            return danger ? colors.error : colors.surfaceContainerHigh;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => danger && highlighted(states)
                ? colors.onError
                : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
