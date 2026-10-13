import 'dart:math' as math;

import 'package:camera/camera.dart';

enum CameraLensKind { ultraWide, wide, telephoto, macro, unknown }

class CameraLensInfo {
  const CameraLensInfo({
    required this.description,
    this.kind = CameraLensKind.unknown,
    this.equivalentFocalLength,
    this.minimumFocusDistance,
    this.supportsManualFocus = false,
    this.maxJpegPixels,
    this.physicalCameraIds = const <String>[],
  });

  factory CameraLensInfo.fromDescription(CameraDescription description) {
    return CameraLensInfo(description: description);
  }

  factory CameraLensInfo.fromPlatformMap(Map<Object?, Object?> map) {
    final id = map['id'] as String;
    final lensFacing = map['lensFacing'] as int;
    final orientation = map['sensorOrientation'] as int;
    final focalLengths = (map['focalLengths'] as List<Object?>? ?? const [])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    final sensorWidth = (map['sensorWidth'] as num?)?.toDouble();
    final sensorHeight = (map['sensorHeight'] as num?)?.toDouble();
    final maxJpegWidth = map['maxJpegWidth'] as int?;
    final maxJpegHeight = map['maxJpegHeight'] as int?;

    double? equivalentFocalLength;
    if (focalLengths.isNotEmpty &&
        sensorWidth != null &&
        sensorHeight != null &&
        sensorWidth > 0 &&
        sensorHeight > 0) {
      final sensorDiagonal = math.sqrt(
        sensorWidth * sensorWidth + sensorHeight * sensorHeight,
      );
      equivalentFocalLength = focalLengths.first * 43.266615 / sensorDiagonal;
    }

    return CameraLensInfo(
      description: CameraDescription(
        name: id,
        lensDirection: _directionFor(lensFacing),
        sensorOrientation: orientation,
      ),
      equivalentFocalLength: equivalentFocalLength,
      minimumFocusDistance: (map['minimumFocusDistance'] as num?)?.toDouble(),
      supportsManualFocus: map['supportsManualFocus'] as bool? ?? false,
      maxJpegPixels: maxJpegWidth != null && maxJpegHeight != null
          ? maxJpegWidth * maxJpegHeight
          : null,
      physicalCameraIds:
          (map['physicalCameraIds'] as List<Object?>? ?? const [])
              .whereType<String>()
              .toList(growable: false),
    );
  }

  final CameraDescription description;
  final CameraLensKind kind;
  final double? equivalentFocalLength;
  final double? minimumFocusDistance;
  final bool supportsManualFocus;
  final int? maxJpegPixels;
  final List<String> physicalCameraIds;

  CameraLensInfo copyWith({CameraLensKind? kind}) {
    return CameraLensInfo(
      description: description,
      kind: kind ?? this.kind,
      equivalentFocalLength: equivalentFocalLength,
      minimumFocusDistance: minimumFocusDistance,
      supportsManualFocus: supportsManualFocus,
      maxJpegPixels: maxJpegPixels,
      physicalCameraIds: physicalCameraIds,
    );
  }

  String displayLabel(int fallbackIndex) {
    return switch (kind) {
      CameraLensKind.ultraWide => 'Ultra wide',
      CameraLensKind.wide => 'Wide',
      CameraLensKind.telephoto => 'Telefoto',
      CameraLensKind.macro => 'Makro',
      CameraLensKind.unknown => 'Camera ${fallbackIndex + 1}',
    };
  }

  static CameraLensDirection _directionFor(int lensFacing) {
    return switch (lensFacing) {
      0 => CameraLensDirection.front,
      2 => CameraLensDirection.external,
      _ => CameraLensDirection.back,
    };
  }
}

class CameraLensClassifier {
  const CameraLensClassifier._();

  static const int _auxiliaryPixelLimit = 6000000;
  static const double _macroFocusDiopters = 20;

  static List<CameraLensInfo> classify(List<CameraLensInfo> lenses) {
    final largestPixelCount = lenses
        .map((lens) => lens.maxJpegPixels ?? 0)
        .fold<int>(0, math.max);

    return lenses
        .map((lens) {
          final normalizedName = lens.description.name.toLowerCase();
          final isExplicitMacro =
              normalizedName.contains('macro') ||
              normalizedName.contains('makro');
          final pixels = lens.maxJpegPixels;
          final isLowResolutionAuxiliary =
              largestPixelCount > 0 &&
              pixels != null &&
              pixels <= _auxiliaryPixelLimit &&
              pixels * 2 < largestPixelCount;
          final focusDistance = lens.minimumFocusDistance;
          final hasMacroLikeFocus =
              focusDistance != null && focusDistance >= _macroFocusDiopters;

          CameraLensKind kind;
          if (isExplicitMacro ||
              (isLowResolutionAuxiliary && hasMacroLikeFocus)) {
            kind = CameraLensKind.macro;
          } else if (isLowResolutionAuxiliary && focusDistance == 0) {
            kind = CameraLensKind.unknown;
          } else if (normalizedName.contains('ultra')) {
            kind = CameraLensKind.ultraWide;
          } else if (normalizedName.contains('tele') ||
              normalizedName.contains('zoom')) {
            kind = CameraLensKind.telephoto;
          } else if (normalizedName.contains('wide')) {
            kind = CameraLensKind.wide;
          } else {
            final equivalent = lens.equivalentFocalLength;
            if (equivalent == null) {
              kind = CameraLensKind.unknown;
            } else if (equivalent < 20) {
              kind = CameraLensKind.ultraWide;
            } else if (equivalent > 50) {
              kind = CameraLensKind.telephoto;
            } else {
              kind = CameraLensKind.wide;
            }
          }

          return lens.copyWith(kind: kind);
        })
        .toList(growable: false);
  }
}
