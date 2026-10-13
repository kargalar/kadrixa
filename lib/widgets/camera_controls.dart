import 'package:flutter/material.dart';
import '../models/capture_mode.dart';

class CameraControlSurface extends StatelessWidget {
  const CameraControlSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 44,
    height: 44,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class CameraControlButton extends StatelessWidget {
  const CameraControlButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip ?? '',
    child: Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: CameraControlSurface(
            child: Icon(
              icon,
              size: 21,
              color: onPressed == null
                  ? Theme.of(context).disabledColor
                  : color ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    ),
  );
}

class CaptureModeSelector extends StatelessWidget {
  const CaptureModeSelector({
    super.key,
    required this.mode,
    required this.onSelected,
  });
  final CaptureMode mode;
  final ValueChanged<CaptureMode> onSelected;
  static const labels = {
    CaptureMode.photo: 'PHOTO',
    CaptureMode.video: 'VIDEO',
    CaptureMode.timeburst: 'TIMEBURST',
    CaptureMode.dualVideo: 'DUAL CAMERA',
  };

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: CaptureMode.values
            .map(
              (value) => Expanded(
                child: Semantics(
                  selected: value == mode,
                  button: true,
                  child: InkWell(
                    onTap: () => onSelected(value),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: value == mode
                            ? Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        labels[value]!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: value == mode
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    ),
  );
}
