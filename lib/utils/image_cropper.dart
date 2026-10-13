import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

class CropRequest {
  final String path;
  final double targetAspectRatio;
  final bool mirrorHorizontally;

  CropRequest(this.path, this.targetAspectRatio, this.mirrorHorizontally);
}

const previewMirrorSoftware = 'Kadrixa:preview-mirrored:v1';

class JpegDimensions {
  const JpegDimensions({required this.width, required this.height});

  final int width;
  final int height;

  @override
  bool operator ==(Object other) {
    return other is JpegDimensions &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);
}

JpegDimensions? readJpegDimensions(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) {
    return null;
  }

  const startOfFrameMarkers = <int>{
    0xc0,
    0xc1,
    0xc2,
    0xc3,
    0xc5,
    0xc6,
    0xc7,
    0xc9,
    0xca,
    0xcb,
    0xcd,
    0xce,
    0xcf,
  };
  var offset = 2;

  while (offset + 1 < bytes.length) {
    if (bytes[offset] != 0xff) {
      offset++;
      continue;
    }
    while (offset < bytes.length && bytes[offset] == 0xff) {
      offset++;
    }
    if (offset >= bytes.length) return null;

    final marker = bytes[offset++];
    if (marker == 0xd9) return null;
    if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd8)) {
      continue;
    }
    if (offset + 1 >= bytes.length) return null;

    final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
    if (segmentLength < 2 || offset + segmentLength > bytes.length) {
      return null;
    }
    if (startOfFrameMarkers.contains(marker)) {
      if (segmentLength < 7) return null;
      final height = (bytes[offset + 3] << 8) | bytes[offset + 4];
      final width = (bytes[offset + 5] << 8) | bytes[offset + 6];
      if (width <= 0 || height <= 0) return null;
      return JpegDimensions(width: width, height: height);
    }
    offset += segmentLength;
  }

  return null;
}

Future<XFile?> cropImageToAspectRatio(
  XFile file,
  double targetAspectRatio, {
  bool mirrorHorizontally = false,
}) async {
  if (!targetAspectRatio.isFinite || targetAspectRatio <= 0) {
    throw ArgumentError.value(targetAspectRatio, 'targetAspectRatio');
  }
  try {
    final newPath = await compute(
      _cropImageIsolate,
      CropRequest(file.path, targetAspectRatio, mirrorHorizontally),
    );
    if (newPath != null) {
      return XFile(newPath);
    }
    return file;
  } catch (e) {
    debugPrint('Error cropping image: $e');
    rethrow;
  }
}

Future<String?> _cropImageIsolate(CropRequest request) async {
  final bytes = await File(request.path).readAsBytes();
  final exif = request.mirrorHorizontally ? img.decodeJpgExif(bytes) : null;
  final needsMirror =
      request.mirrorHorizontally &&
      exif?.imageIfd['Software']?.toString() != previewMirrorSoftware;
  final dimensions = readJpegDimensions(bytes);
  if (dimensions != null && !needsMirror) {
    final currentAspectRatio = dimensions.width >= dimensions.height
        ? dimensions.width / dimensions.height
        : dimensions.height / dimensions.width;
    if ((currentAspectRatio - request.targetAspectRatio).abs() < 0.05) {
      return request.path;
    }
  }
  final image = img.decodeJpg(bytes);

  if (image == null) {
    throw const FormatException('Could not decode the photo as JPEG.');
  }

  if (needsMirror) {
    // The JPEG decoder already applies EXIF rotation and reflection. Mirror
    // along the displayed horizontal axis, unless EXIF already mirrors it.
    const mirroredOrientations = {2, 4, 5, 7};
    if (!mirroredOrientations.contains(exif?.imageIfd.orientation)) {
      img.flipHorizontal(image);
    }
    image.exif.imageIfd['Software'] = previewMirrorSoftware;
    image.exif.imageIfd.orientation = 1;
  }

  // JPEG decoding applies EXIF rotation. Keep portrait captures portrait when
  // cropping to the user's landscape-labelled ratio (4:3 or 16:9).
  final targetAspectRatio = image.width >= image.height
      ? request.targetAspectRatio
      : 1 / request.targetAspectRatio;

  final double currentAspectRatio = image.width / image.height;

  // Tolerance for float comparison
  if ((currentAspectRatio - targetAspectRatio).abs() < 0.05 && !needsMirror) {
    return null; // No need to crop
  }

  int targetWidth = image.width;
  int targetHeight = image.height;

  if (currentAspectRatio > targetAspectRatio) {
    // Current is wider, we need to crop the width (left and right)
    targetWidth = (image.height * targetAspectRatio).round().clamp(
      1,
      image.width,
    );
  } else {
    // Current is taller, we need to crop the height (top and bottom)
    targetHeight = (image.width / targetAspectRatio).round().clamp(
      1,
      image.height,
    );
  }

  final x = (image.width - targetWidth) ~/ 2;
  final y = (image.height - targetHeight) ~/ 2;

  final croppedImage = img.copyCrop(
    image,
    x: x,
    y: y,
    width: targetWidth,
    height: targetHeight,
  );
  final croppedBytes = img.encodeJpg(croppedImage, quality: 92);

  final file = File(request.path);
  final temporary = File('${request.path}.crop.tmp');
  try {
    await temporary.writeAsBytes(croppedBytes, flush: true);
    try {
      await temporary.rename(file.path);
    } on FileSystemException {
      if (!Platform.isWindows) rethrow;
      await temporary.copy(file.path);
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }

  return request.path;
}
