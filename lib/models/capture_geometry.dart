import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

/// The frame shown in the viewfinder and retained in the saved video.
abstract final class CaptureGeometry {
  static int? resolutionShortEdge(ResolutionPreset preset) => switch (preset) {
    ResolutionPreset.low => 240,
    ResolutionPreset.medium => 480,
    ResolutionPreset.high => 720,
    ResolutionPreset.veryHigh => 1080,
    ResolutionPreset.ultraHigh => 2160,
    ResolutionPreset.max => null,
  };

  static ({int width, int height}) videoSize(
    int width,
    int height,
    double? aspectRatio,
    ResolutionPreset preset,
  ) {
    final crop = aspectRatio == null
        ? (width: width, height: height)
        : cropSize(width, height, aspectRatio);
    final maximumEdge = resolutionShortEdge(preset);
    final shortEdge = math.min(crop.width, crop.height);
    if (maximumEdge == null || shortEdge <= maximumEdge) return crop;
    return frameSize(maximumEdge, crop.width / crop.height);
  }

  static int rotationDegrees(DeviceOrientation orientation) =>
      switch (orientation) {
        DeviceOrientation.portraitUp => 0,
        DeviceOrientation.landscapeLeft => 90,
        DeviceOrientation.portraitDown => 180,
        DeviceOrientation.landscapeRight => 270,
      };

  static ({int width, int height}) frameSize(int shortEdge, double ratio) {
    final width = ratio >= 1 ? (shortEdge * ratio).round() : shortEdge;
    final height = ratio >= 1 ? shortEdge : (shortEdge / ratio).round();
    return (width: width - width % 2, height: height - height % 2);
  }

  static bool isLandscape(DeviceOrientation orientation) =>
      orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;

  static double orientedAspectRatio(
    double ratio,
    DeviceOrientation orientation,
  ) => isLandscape(orientation) ? ratio : 1 / ratio;

  static ({int width, int height}) cropSize(
    int width,
    int height,
    double aspectRatio,
  ) {
    if (width <= 0 ||
        height <= 0 ||
        !aspectRatio.isFinite ||
        aspectRatio <= 0) {
      throw ArgumentError('Invalid capture dimensions or aspect ratio.');
    }
    final cropWidth = math.min(width, (height * aspectRatio).round());
    final cropHeight = math.min(height, (width / aspectRatio).round());
    // H.264 YUV420 requires even dimensions.
    return (
      width: cropWidth - cropWidth % 2,
      height: cropHeight - cropHeight % 2,
    );
  }
}
