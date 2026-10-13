import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../models/camera_lens_info.dart';

class CameraLensSelector extends StatelessWidget {
  const CameraLensSelector({
    required this.lenses,
    required this.selectedCameraId,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final List<CameraLensInfo> lenses;
  final String? selectedCameraId;
  final ValueChanged<CameraDescription> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (lenses.length <= 1) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 8,
        children: List.generate(lenses.length, (index) {
          final lens = lenses[index];
          final camera = lens.description;
          final selected = selectedCameraId == camera.name;
          final duplicates = lenses.where((other) => other.kind == lens.kind);
          final label = lens.displayLabel(index);
          return ChoiceChip(
            key: ValueKey('camera_lens_${camera.name}'),
            label: Text(
              duplicates.length > 1 && lens.kind != CameraLensKind.unknown
                  ? '$label (${camera.name})'
                  : label,
            ),
            selected: selected,
            showCheckmark: false,
            onSelected: enabled
                ? (_) {
                    if (!selected) onSelected(camera);
                  }
                : null,
          );
        }),
      ),
    );
  }
}
