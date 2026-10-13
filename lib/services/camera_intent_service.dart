import 'package:flutter/services.dart';
import '../constants/app_brand.dart';
import '../models/capture_mode.dart';

class CameraLaunchRequest {
  const CameraLaunchRequest({
    required this.mode,
    required this.returnCapture,
    this.durationLimitSeconds = 0,
    this.lowVideoQuality = false,
  });
  final CaptureMode mode;
  final bool returnCapture;
  final int durationLimitSeconds;
  final bool lowVideoQuality;

  factory CameraLaunchRequest.fromMap(Map<Object?, Object?> map) =>
      CameraLaunchRequest(
        mode: map['mode'] == 'video' ? CaptureMode.video : CaptureMode.photo,
        returnCapture: map['returnCapture'] == true,
        durationLimitSeconds: (map['durationLimitSeconds'] as int? ?? 0).clamp(
          0,
          86400,
        ),
        lowVideoQuality: map['lowVideoQuality'] == true,
      );
}

abstract final class CameraIntentService {
  static const channel = MethodChannel(
    '${AppBrand.applicationId}/camera_intents',
  );

  static Future<CameraLaunchRequest?> loadRequest() async {
    try {
      final map = await channel.invokeMapMethod<Object?, Object?>(
        'getLaunchRequest',
      );
      return map == null ? null : CameraLaunchRequest.fromMap(map);
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> complete(String path) =>
      channel.invokeMethod<void>('completeCapture', {'path': path});
  static Future<void> cancel() => channel.invokeMethod<void>('cancelCapture');
  static Future<void> openCameraSelector() =>
      channel.invokeMethod<void>('openCameraSelector');
}
