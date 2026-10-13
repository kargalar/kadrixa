import 'package:gal/gal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../constants/app_brand.dart';

class StorageService {
  static const _channel = MethodChannel(
    '${AppBrand.applicationId}/media_pipeline',
  );

  /// Save an image file to the device gallery (DCIM/Camera)
  static Future<bool> saveImageToGallery(String imagePath) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<String>('saveImageToGallery', {
          'path': imagePath,
        });
      } else {
        await Gal.putImage(imagePath);
      }
      return true;
    } catch (e) {
      debugPrint('Error saving image to gallery: $e');
      return false;
    }
  }

  /// Save a video file to the device gallery (DCIM/Camera)
  static Future<bool> saveVideoToGallery(String videoPath) async {
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<String>('saveVideoToGallery', {
          'path': videoPath,
        });
      } else {
        await Gal.putVideo(videoPath);
      }
      return true;
    } catch (e) {
      debugPrint('Error saving video to gallery: $e');
      return false;
    }
  }

  /// Check if gallery access is available
  static Future<bool> hasAccess() async {
    return await Gal.hasAccess();
  }

  /// Request gallery access
  static Future<bool> requestAccess() async {
    return await Gal.requestAccess();
  }
}
