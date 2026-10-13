import 'dart:io';

import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import '../constants/app_brand.dart';
import '../models/capture_geometry.dart';

class DualCameraPreview {
  const DualCameraPreview({
    required this.textureId,
    required this.width,
    required this.height,
  });

  final int textureId;
  final double width;
  final double height;
  double get aspectRatio => width / height;

  factory DualCameraPreview.fromMap(Map<Object?, Object?> data) =>
      DualCameraPreview(
        textureId: (data['textureId'] as num).toInt(),
        width: (data['width'] as num).toDouble(),
        height: (data['height'] as num).toDouble(),
      );
}

class DualCameraService {
  static const _channel = MethodChannel(
    '${AppBrand.applicationId}/dual_camera',
  );
  static const _events = EventChannel(
    '${AppBrand.applicationId}/dual_camera/events',
  );

  late final _eventStream = _events
      .receiveBroadcastStream()
      .cast<Map<Object?, Object?>>();
  Stream<String> get errors => _eventStream
      .where((event) => event['error'] != null)
      .map((event) => event['error'] as String);

  Stream<DeviceOrientation> get orientations => _eventStream
      .where((event) => event['orientation'] != null)
      .map(
        (event) =>
            DeviceOrientation.values.byName(event['orientation'] as String),
      );

  static Map<String, int> frameConfiguration({
    required double aspectRatio,
    required ResolutionPreset resolutionPreset,
    required DeviceOrientation orientation,
  }) {
    // Concurrent camera streams on Android are guaranteed only up to 720p.
    final shortEdge = switch (resolutionPreset) {
      ResolutionPreset.low => 240,
      ResolutionPreset.medium => 480,
      _ => 720,
    };
    final size = CaptureGeometry.frameSize(
      shortEdge,
      CaptureGeometry.orientedAspectRatio(aspectRatio, orientation),
    );
    return {
      'width': size.width,
      'height': size.height,
      'rotation': CaptureGeometry.rotationDegrees(orientation),
    };
  }

  Future<DualCameraPreview> initialize({
    double aspectRatio = 16 / 9,
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
    DeviceOrientation orientation = DeviceOrientation.portraitUp,
  }) async {
    if (!Platform.isAndroid) {
      throw PlatformException(
        code: 'dualCameraUnavailable',
        message:
            'Dual-camera mode is currently available only on Android devices.',
      );
    }
    final data = await _channel.invokeMapMethod<Object?, Object?>(
      'initialize',
      frameConfiguration(
        aspectRatio: aspectRatio,
        resolutionPreset: resolutionPreset,
        orientation: orientation,
      ),
    );
    if (data == null) throw StateError('Could not start the camera preview.');
    return DualCameraPreview.fromMap(data);
  }

  Future<DualCameraPreview> configure({
    required double aspectRatio,
    required ResolutionPreset resolutionPreset,
    required DeviceOrientation orientation,
  }) async {
    final data = await _channel.invokeMapMethod<Object?, Object?>(
      'configure',
      frameConfiguration(
        aspectRatio: aspectRatio,
        resolutionPreset: resolutionPreset,
        orientation: orientation,
      ),
    );
    if (data == null) throw StateError('Could not prepare the camera frame.');
    return DualCameraPreview.fromMap(data);
  }

  Future<void> swap({required bool frontIsMain}) =>
      _channel.invokeMethod<void>('swap', {'frontIsMain': frontIsMain});

  Future<void> startRecording({String? microphoneId}) => _channel
      .invokeMethod<void>('startRecording', {'microphoneId': microphoneId});

  Future<String?> stopRecording() =>
      _channel.invokeMethod<String>('stopRecording');

  Future<void> dispose() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('dispose');
  }
}
