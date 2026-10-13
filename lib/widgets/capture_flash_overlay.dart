import 'package:flutter/material.dart';

class CaptureFlashOverlay extends StatelessWidget {
  const CaptureFlashOverlay({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 0.88 : 0,
        duration: const Duration(milliseconds: 55),
        curve: Curves.easeOut,
        child: ColoredBox(color: Theme.of(context).colorScheme.scrim),
      ),
    );
  }
}
