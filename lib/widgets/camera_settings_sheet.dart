import 'package:flutter/material.dart';
import '../constants/app_brand.dart';

class CameraSettingsSheet extends StatelessWidget {
  const CameraSettingsSheet({
    super.key,
    required this.waveformVisible,
    required this.onToggleWaveform,
    required this.onOpenDefaults,
  });
  final bool waveformVisible;
  final VoidCallback onToggleWaveform;
  final VoidCallback onOpenDefaults;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(
            'Camera settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.graphic_eq_rounded),
            title: const Text('Audio waveform'),
            subtitle: const Text('Show it on the video screen'),
            value: waveformVisible,
            onChanged: (_) => onToggleWaveform(),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('Default camera'),
            subtitle: const Text('Open camera app selection'),
            trailing: const Icon(Icons.open_in_new_rounded, size: 20),
            onTap: onOpenDefaults,
          ),
          Text(
            'Choose ${AppBrand.name} and Always on the selection screen. Depending on your Android version, some apps may only open the system camera.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
