import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../constants/app_brand.dart';
import '../models/media_location.dart';
import '../utils/image_cropper.dart';
import 'storage_service.dart';

typedef PhotoCropper =
    Future<XFile?> Function(
      XFile file,
      double targetAspectRatio, {
      bool mirrorHorizontally,
    });
typedef GalleryImageSaver = Future<bool> Function(String imagePath);

class PhotoProcessingResult {
  const PhotoProcessingResult({
    required this.success,
    required this.path,
    required this.didCrop,
    this.galleryUri,
  });

  final bool success;
  final String path;
  final bool didCrop;
  final String? galleryUri;
}

/// Processes still images outside the UI isolate.
///
/// Android uses a native region decoder and writes directly to MediaStore.
/// Other platforms, and Android devices where the platform channel is not
/// available, keep using the existing Dart implementation as a safe fallback.
class PhotoProcessingService {
  factory PhotoProcessingService({
    MethodChannel channel = const MethodChannel(
      '${AppBrand.applicationId}/photo_processing',
    ),
    bool? useNativeAndroidPipeline,
    PhotoCropper fallbackCrop = cropImageToAspectRatio,
    GalleryImageSaver fallbackSave = StorageService.saveImageToGallery,
  }) {
    return PhotoProcessingService._(
      channel,
      useNativeAndroidPipeline ?? (!kIsWeb && Platform.isAndroid),
      fallbackCrop,
      fallbackSave,
    );
  }

  PhotoProcessingService._(
    this._channel,
    this._useNativeAndroidPipeline,
    this._fallbackCrop,
    this._fallbackSave,
  );

  static final PhotoProcessingService instance = PhotoProcessingService();

  final MethodChannel _channel;
  final bool _useNativeAndroidPipeline;
  final PhotoCropper _fallbackCrop;
  final GalleryImageSaver _fallbackSave;

  Future<PhotoProcessingResult> process(
    XFile source, {
    required double targetAspectRatio,
    required bool saveToGallery,
    bool mirrorHorizontally = false,
    int jpegQuality = 95,
    MediaLocation? location,
  }) async {
    if (_useNativeAndroidPipeline) {
      try {
        final nativeResult = await _channel.invokeMapMethod<String, Object?>(
          'processAndSavePhoto',
          <String, Object?>{
            'sourcePath': source.path,
            'targetAspectRatio': targetAspectRatio,
            'jpegQuality': jpegQuality,
            'saveToGallery': saveToGallery,
            'mirrorHorizontally': mirrorHorizontally,
            if (location != null) ...location.toJson(),
          },
        );

        final path = nativeResult?['path'] as String?;
        if (nativeResult?['success'] == true &&
            path != null &&
            path.isNotEmpty) {
          return PhotoProcessingResult(
            success: true,
            path: path,
            didCrop: nativeResult?['didCrop'] == true,
            galleryUri: nativeResult?['galleryUri'] as String?,
          );
        }
      } on MissingPluginException catch (error) {
        debugPrint('Native photo processor is unavailable: $error');
      } on PlatformException catch (error) {
        debugPrint('Native photo processing failed: $error');
        rethrow;
      }
    }

    final croppedFile = await _fallbackCrop(
      source,
      targetAspectRatio,
      mirrorHorizontally: mirrorHorizontally,
    );
    final finalFile = croppedFile ?? source;
    if (location != null) {
      await _writeLocationToJpeg(finalFile.path, location);
    }
    final saved = !saveToGallery || await _fallbackSave(finalFile.path);

    return PhotoProcessingResult(
      success: saved,
      path: finalFile.path,
      didCrop: finalFile.path != source.path,
    );
  }

  static Future<void> _writeLocationToJpeg(
    String filePath,
    MediaLocation location,
  ) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final exif = img.decodeJpgExif(bytes) ?? img.ExifData();
    final gps = exif.gpsIfd;

    gps['GPSVersionID'] = <int>[2, 2, 0, 0];
    gps['GPSLatitudeRef'] = location.latitude >= 0 ? 'N' : 'S';
    gps['GPSLatitude'] = _toDmsRationals(location.latitude.abs());
    gps['GPSLongitudeRef'] = location.longitude >= 0 ? 'E' : 'W';
    gps['GPSLongitude'] = _toDmsRationals(location.longitude.abs());

    if (location.altitude != null) {
      gps['GPSAltitudeRef'] = location.altitude! < 0 ? 1 : 0;
      gps['GPSAltitude'] = <List<int>>[
        <int>[(location.altitude!.abs() * 100).round(), 100],
      ];
    }

    final updatedBytes = img.injectJpgExif(bytes, exif);
    if (updatedBytes == null) {
      throw StateError('Could not write the photo EXIF location.');
    }
    await file.writeAsBytes(updatedBytes, flush: true);
  }

  static List<List<int>> _toDmsRationals(double coordinate) {
    final degrees = coordinate.floor();
    final minutesWithFraction = (coordinate - degrees) * 60;
    final minutes = minutesWithFraction.floor();
    final seconds = (minutesWithFraction - minutes) * 60;
    const denominator = 1000000;
    return <List<int>>[
      <int>[degrees, 1],
      <int>[minutes, 1],
      <int>[(seconds * denominator).round(), denominator],
    ];
  }
}
