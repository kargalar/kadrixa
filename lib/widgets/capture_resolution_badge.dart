import 'package:flutter/material.dart';

class CaptureResolutionBadge extends StatelessWidget {
  const CaptureResolutionBadge({
    super.key,
    required this.width,
    required this.height,
  });

  final int width;
  final int height;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Text(
        '$width × $height',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ),
  );
}
