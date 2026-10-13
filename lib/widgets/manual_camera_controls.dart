import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum ManualCameraSetting { iso, shutter, focus }

abstract final class ManualCameraStrings {
  static const auto = 'Return to automatic settings';
  static const focusUnsupported = 'Bu lenste manuel odak desteklenmiyor';
  static const focusFailed = 'Could not apply manual focus.';
  static const cameraSwitch = 'Switch front/rear camera';
  static const labels = {
    ManualCameraSetting.iso: 'ISO',
    ManualCameraSetting.shutter: 'Enstantane',
    ManualCameraSetting.focus: 'Odak',
  };
}

class ManualCameraControls extends StatelessWidget {
  const ManualCameraControls({
    super.key,
    required this.selected,
    required this.iso,
    required this.shutterNanos,
    required this.focusDistance,
    required this.maximumFocusDistance,
    required this.enabled,
    required this.onSelected,
    required this.onIsoChanged,
    required this.onShutterChanged,
    required this.onFocusChanged,
    required this.onAuto,
  });

  static const height = 128.0;
  static const minIso = 100;
  static const maxIso = 3200;
  static const isoStep = 100;
  static const minShutterNanos = 1000000;
  static const maxShutterNanos = 500000000;
  static const nanosPerSecond = 1000000000;
  static const controlRowHeight = 48.0;

  final ManualCameraSetting selected;
  final int iso;
  final int shutterNanos;
  final double focusDistance;
  final double maximumFocusDistance;
  final bool enabled;
  final ValueChanged<ManualCameraSetting> onSelected;
  final ValueChanged<int> onIsoChanged;
  final ValueChanged<int> onShutterChanged;
  final ValueChanged<double> onFocusChanged;
  final VoidCallback onAuto;

  @override
  Widget build(BuildContext context) {
    final supportsFocus = maximumFocusDistance > 0;
    final values = {
      ManualCameraSetting.iso: '$iso',
      ManualCameraSetting.shutter:
          '1/${(nanosPerSecond / shutterNanos).round()} s',
      ManualCameraSetting.focus: !supportsFocus
          ? '—'
          : focusDistance == 0
          ? '∞'
          : '${(100 / focusDistance).round()} cm',
    };
    final min = switch (selected) {
      ManualCameraSetting.iso => minIso.toDouble(),
      ManualCameraSetting.shutter => minShutterNanos.toDouble(),
      ManualCameraSetting.focus => 0.0,
    };
    final max = switch (selected) {
      ManualCameraSetting.iso => maxIso.toDouble(),
      ManualCameraSetting.shutter => maxShutterNanos.toDouble(),
      ManualCameraSetting.focus => supportsFocus ? maximumFocusDistance : 1.0,
    };
    final value = switch (selected) {
      ManualCameraSetting.iso => iso.toDouble(),
      ManualCameraSetting.shutter => shutterNanos.toDouble(),
      ManualCameraSetting.focus => focusDistance,
    };
    final sliderEnabled =
        enabled && (selected != ManualCameraSetting.focus || supportsFocus);
    return SizedBox(
      height: height,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              SizedBox(
                height: controlRowHeight,
                child: Row(
                  children: [
                    for (final setting in ManualCameraSetting.values)
                      Expanded(
                        child: _ManualSettingButton(
                          setting: setting,
                          value: values[setting]!,
                          selected: selected == setting,
                          onPressed: () => onSelected(setting),
                        ),
                      ),
                    IconButton(
                      tooltip: ManualCameraStrings.auto,
                      icon: const Icon(Icons.settings_backup_restore, size: 20),
                      onPressed: enabled ? onAuto : null,
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: controlRowHeight,
                child: Slider(
                  key: ValueKey('manual_${selected.name}_slider'),
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: selected == ManualCameraSetting.iso
                      ? (maxIso - minIso) ~/ isoStep
                      : null,
                  label: values[selected],
                  onChanged: !sliderEnabled
                      ? null
                      : (value) {
                          switch (selected) {
                            case ManualCameraSetting.iso:
                              onIsoChanged(value.round());
                            case ManualCameraSetting.shutter:
                              onShutterChanged(value.round());
                            case ManualCameraSetting.focus:
                              onFocusChanged(value);
                          }
                        },
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    selected == ManualCameraSetting.focus && !supportsFocus
                        ? ManualCameraStrings.focusUnsupported
                        : '${ManualCameraStrings.labels[selected]} · ${values[selected]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualSettingButton extends StatelessWidget {
  const _ManualSettingButton({
    required this.setting,
    required this.value,
    required this.selected,
    required this.onPressed,
  });
  final ManualCameraSetting setting;
  final String value;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('manual_${setting.name}_tab'),
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Ink(
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ManualCameraStrings.labels[setting]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
