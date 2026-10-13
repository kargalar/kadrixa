import 'dart:io';

import 'package:flutter/material.dart';

class PhotoCaptureFlight extends StatefulWidget {
  const PhotoCaptureFlight({
    super.key,
    required this.imagePath,
    required this.begin,
    required this.end,
    required this.onCompleted,
  });

  final String imagePath;
  final Rect begin;
  final Rect end;
  final VoidCallback onCompleted;

  @override
  State<PhotoCaptureFlight> createState() => _PhotoCaptureFlightState();
}

class _PhotoCaptureFlightState extends State<PhotoCaptureFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  late final Animation<Rect?> _rect;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
    _rect = RectTween(begin: widget.begin, end: widget.end).animate(_curve);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) {
          final rect = _rect.value ?? widget.end;
          return Stack(
            children: [
              Positioned.fromRect(
                rect: rect,
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12 * _curve.value),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.shadow.withValues(alpha: 0.4),
                          blurRadius: 16 * _curve.value,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12 * _curve.value),
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.cover,
                        cacheWidth: 720,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
