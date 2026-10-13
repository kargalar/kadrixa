import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraPreviewGuard extends StatelessWidget {
  const CameraPreviewGuard({
    required this.controller,
    required this.child,
    required this.onRecover,
    super.key,
  });

  final CameraController controller;
  final Widget child;
  final VoidCallback onRecover;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      child: child,
      builder: (context, value, preview) {
        if (value.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 16,
              children: [
                Text(
                  'Camera connection was lost.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                FilledButton.icon(
                  onPressed: onRecover,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Return to main camera'),
                ),
              ],
            ),
          );
        }
        if (!value.isInitialized) {
          return const Center(child: CircularProgressIndicator());
        }
        return preview!;
      },
    );
  }
}
