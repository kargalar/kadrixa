import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_brand.dart';
import '../models/camera_lens_info.dart';
import 'photo_processing_service.dart';
import 'preferences_service.dart';

class CameraService {
  static const MethodChannel _channel = MethodChannel(
    '${AppBrand.applicationId}/cameras',
  );
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  List<CameraDescription> _backCameras = [];
  List<CameraDescription> _frontCameras = [];
  List<CameraLensInfo> _backLensInfos = [];
  List<CameraLensInfo> _lensInfos = [];
  double? _manualFocusDistance;
  int _currentBackCameraIndex = 0;
  bool _isFrontCamera = false;
  ResolutionPreset _resolutionPreset = ResolutionPreset.max;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _aspectRatio = 4 / 3; // Default to 4:3
  FlashMode _flashMode = FlashMode.auto;
  double _minExposure = -2.0;
  double _maxExposure = 2.0;
  double _currentExposure = 0.0;
  DeviceOrientation? _recordingOrientation;
  bool _videoPreviewEnabled = false;

  CameraController? get controller => _controller;
  List<CameraDescription> get cameras => _cameras;
  List<CameraDescription> get backCameras => _backCameras;
  List<CameraDescription> get frontCameras => _frontCameras;
  List<CameraLensInfo> get backLensInfos => _backLensInfos;
  int get currentBackCameraIndex => _currentBackCameraIndex;
  bool get isFrontCamera => _isFrontCamera;
  ResolutionPreset get resolutionPreset => _resolutionPreset;
  double get minZoom => _minZoom;
  double get maxZoom => _maxZoom;
  double get currentZoom => _currentZoom;
  double get aspectRatio => _aspectRatio;
  FlashMode get flashMode => _flashMode;
  double get minExposure => _minExposure;
  double get maxExposure => _maxExposure;
  double get currentExposure => _currentExposure;
  String? get currentCameraId => _controller?.description.name;
  double get maximumFocusDistance {
    for (final lens in _lensInfos) {
      if (lens.description.name == currentCameraId &&
          lens.supportsManualFocus) {
        return lens.minimumFocusDistance ?? 0;
      }
    }
    return 0;
  }

  bool get supportsManualFocus => maximumFocusDistance > 0;
  double? get manualFocusDistance => _manualFocusDistance;

  bool get isInitialized =>
      (_controller?.value.isInitialized ?? false) &&
      !(_controller?.value.hasError ?? true);
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  /// Returns the aspect ratio of the camera preview
  double get previewAspectRatio {
    if (_controller == null || !_controller!.value.isInitialized) return 16 / 9;
    return _controller!.value.aspectRatio;
  }

  Future<List<CameraLensInfo>> retrieveAllPhysicalCameras() async {
    try {
      final List<dynamic>? nativeCameras = await _channel.invokeMethod(
        'getAllPhysicalCameras',
      );
      if (nativeCameras == null || nativeCameras.isEmpty) {
        return (await availableCameras())
            .map(CameraLensInfo.fromDescription)
            .toList(growable: false);
      }
      final List<CameraLensInfo> list = [];
      for (final cam in nativeCameras) {
        final Map<Object?, Object?> map = cam as Map<Object?, Object?>;
        list.add(CameraLensInfo.fromPlatformMap(map));
      }
      return list;
    } catch (e) {
      debugPrint(
        "Native camera list error: $e. Falling back to default availableCameras.",
      );
      return (await availableCameras())
          .map(CameraLensInfo.fromDescription)
          .toList(growable: false);
    }
  }

  Future<void> setManualISO(int iso) async {
    try {
      await _channel.invokeMethod('setManualISO', {'iso': iso});
    } catch (e) {
      debugPrint("Error setting manual ISO: $e");
    }
  }

  Future<void> setManualShutter(int shutterNanos) async {
    try {
      await _channel.invokeMethod('setManualShutter', {
        'shutterNanos': shutterNanos,
      });
    } catch (e) {
      debugPrint("Error setting manual shutter: $e");
    }
  }

  Future<void> setManualFocus(double focusDistance) async {
    if (!focusDistance.isFinite) {
      throw ArgumentError.value(focusDistance, 'focusDistance');
    }
    if (!supportsManualFocus) {
      throw UnsupportedError('This lens has no manual focus.');
    }
    final distance = focusDistance.clamp(0.0, maximumFocusDistance);
    await _channel.invokeMethod<void>('setManualFocus', {
      'focusDistance': distance,
    });
    _manualFocusDistance = distance;
  }

  Future<void> setAutoMode() async {
    _manualFocusDistance = null;
    try {
      await _channel.invokeMethod('setAutoMode');
    } catch (e) {
      debugPrint("Error setting auto mode: $e");
    }
  }

  Future<void> initialize({bool videoPreviewEnabled = false}) async {
    _videoPreviewEnabled = videoPreviewEnabled;
    // Load persisted settings
    _resolutionPreset = await PreferencesService.loadResolution();
    _aspectRatio = await PreferencesService.loadAspectRatio();
    _flashMode = await PreferencesService.loadFlashMode();
    await _applyPhotoCaptureAspectRatio();

    final savedCameraId = await PreferencesService.loadSelectedCameraId();
    final lensInfos = await retrieveAllPhysicalCameras();
    _lensInfos = lensInfos;
    _cameras = lensInfos
        .map((lens) => lens.description)
        .toList(growable: false);

    // Separate back and front cameras
    _backLensInfos = CameraLensClassifier.classify(
      lensInfos
          .where(
            (lens) =>
                lens.description.lensDirection == CameraLensDirection.back,
          )
          .toList(growable: false),
    );
    _backCameras = _backLensInfos
        .map((lens) => lens.description)
        .toList(growable: false);
    _frontCameras = _cameras
        .where((c) => c.lensDirection == CameraLensDirection.front)
        .toList();

    if (_backCameras.isNotEmpty) {
      final savedIndex = _backCameras.indexWhere(
        (camera) => camera.name == savedCameraId,
      );
      _currentBackCameraIndex = savedIndex >= 0 ? savedIndex : 0;
      _isFrontCamera = false;
      try {
        await _initCameraController(_backCameras[_currentBackCameraIndex]);
      } catch (error) {
        if (_currentBackCameraIndex == 0) rethrow;
        debugPrint(
          'Saved lens is unavailable; opening the primary camera: $error',
        );
        _currentBackCameraIndex = 0;
        await _initCameraController(_backCameras.first);
        await PreferencesService.saveSelectedCameraId(_backCameras.first.name);
      }
    } else if (_frontCameras.isNotEmpty) {
      _isFrontCamera = true;
      await _initCameraController(_frontCameras.first);
    }
  }

  Future<void> reinitializeCurrentCamera() async {
    if (_cameras.isEmpty) return;

    CameraDescription currentCamera;
    if (_isFrontCamera && _frontCameras.isNotEmpty) {
      currentCamera = _frontCameras.first;
    } else if (_backCameras.isNotEmpty) {
      if (_currentBackCameraIndex >= 0 &&
          _currentBackCameraIndex < _backCameras.length) {
        currentCamera = _backCameras[_currentBackCameraIndex];
      } else {
        currentCamera = _backCameras.first;
      }
    } else {
      currentCamera = _cameras.first;
    }

    await _initCameraController(currentCamera);
  }

  Future<void> _initCameraController(
    CameraDescription cameraDescription,
  ) async {
    try {
      if (_controller != null) {
        await _controller!.dispose();
      }
      _controller = CameraController(
        cameraDescription,
        _resolutionPreset,
        enableAudio: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      if (_manualFocusDistance != null) {
        if (supportsManualFocus) {
          await setManualFocus(_manualFocusDistance!);
        } else {
          _manualFocusDistance = null;
        }
      }
      if (_recordingOrientation != null) {
        await _controller!.lockCaptureOrientation(_recordingOrientation);
      }
      try {
        await _controller!.setFlashMode(_flashMode);
      } catch (e) {
        debugPrint("Error setting initial flash mode: $e");
      }
      try {
        _minExposure = await _controller!.getMinExposureOffset();
        _maxExposure = await _controller!.getMaxExposureOffset();
        await _controller!.setExposureOffset(
          _currentExposure.clamp(_minExposure, _maxExposure),
        );
      } catch (e) {
        debugPrint("Error setting exposure details: $e");
      }
      await updateZoomRange();
      _currentZoom = _minZoom;
    } catch (e) {
      debugPrint("Camera controller startup failed: $e");
      await _controller?.dispose();
      _controller = null;
      rethrow;
    }
  }

  Future<void> updateZoomRange() async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        _minZoom = await _controller!.getMinZoomLevel();
        _maxZoom = await _controller!.getMaxZoomLevel();
      } catch (e) {
        debugPrint("Could not get zoom limits: $e");
        _minZoom = 1.0;
        _maxZoom = 1.0;
      }
    }
  }

  Future<void> setZoom(double value) async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        final clamped = value.clamp(_minZoom, _maxZoom);
        await _controller!.setZoomLevel(clamped);
        _currentZoom = clamped;
      } catch (e) {
        debugPrint("Could not set zoom: $e");
      }
    }
  }

  Future<void> switchBackLens(int index) async {
    if (index < 0 || index >= _backCameras.length) return;
    await switchCamera(_backCameras[index]);
  }

  Future<void> toggleFrontBack() async {
    if (_isFrontCamera && _backCameras.isNotEmpty) {
      await switchCamera(_backCameras[_currentBackCameraIndex]);
    } else if (!_isFrontCamera && _frontCameras.isNotEmpty) {
      await switchCamera(_frontCameras.first);
    }
  }

  /// Commit the selected lens only after it opens; restore the previous one on failure.
  Future<void> switchCamera(CameraDescription camera) async {
    final matches = _cameras.where(
      (candidate) => candidate.name == camera.name,
    );
    if (matches.isEmpty || (currentCameraId == camera.name && isInitialized)) {
      return;
    }
    final selectedCamera = matches.first;
    final previousCamera = _controller?.description;
    try {
      await _initCameraController(selectedCamera);
    } catch (error, stackTrace) {
      if (previousCamera != null) {
        try {
          await _initCameraController(previousCamera);
        } catch (restoreError) {
          debugPrint('Previous camera could not be restored: $restoreError');
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    _isFrontCamera = selectedCamera.lensDirection == CameraLensDirection.front;
    if (selectedCamera.lensDirection == CameraLensDirection.back) {
      _currentBackCameraIndex = _backCameras.indexWhere(
        (candidate) => candidate.name == selectedCamera.name,
      );
      await PreferencesService.saveSelectedCameraId(selectedCamera.name);
    }
  }

  /// Returns a user-friendly name for a camera description.
  String getCameraName(CameraDescription camera) {
    if (camera.lensDirection == CameraLensDirection.front) {
      final frontIdx = _frontCameras.indexOf(camera);
      if (_frontCameras.length <= 1) {
        return "Front camera";
      } else {
        return "Front camera ${frontIdx + 1}";
      }
    } else if (camera.lensDirection == CameraLensDirection.external) {
      return "External camera";
    } else {
      final backIdx = _backLensInfos.indexWhere(
        (lens) => lens.description.name == camera.name,
      );
      if (backIdx == -1) return "Camera";
      return _backLensInfos[backIdx].displayLabel(backIdx);
    }
  }

  /// Reconfigure the viewfinder and recorder with the same resolution.
  Future<void> setResolution(
    ResolutionPreset preset, {
    bool persist = true,
  }) async {
    if (_resolutionPreset == preset || isRecording) return;
    _resolutionPreset = preset;
    if (persist) await PreferencesService.saveResolution(preset);
    if (isInitialized) await reinitializeCurrentCamera();
  }

  /// Change target aspect ratio
  Future<void> setAspectRatio(double ratio) async {
    if (isRecording) return;
    if ((_aspectRatio - ratio).abs() < 0.001) return;
    _aspectRatio = ratio;
    await PreferencesService.saveAspectRatio(ratio);
    await _applyPhotoCaptureAspectRatio();

    if (isInitialized) {
      final currentCamera = _isFrontCamera
          ? _frontCameras.first
          : _backCameras[_currentBackCameraIndex];
      await _initCameraController(currentCamera);
    }
  }

  Future<void> _applyPhotoCaptureAspectRatio() async {
    try {
      await _channel.invokeMethod<void>('setPhotoCaptureAspectRatio', {
        'ratio': _aspectRatio,
        'videoPreview': _videoPreviewEnabled,
      });
    } on MissingPluginException {
      // Non-Android platforms keep their default camera output size.
    } on PlatformException catch (error) {
      debugPrint('Photo aspect ratio could not be applied: $error');
    }
  }

  Future<void> setVideoPreviewEnabled(bool enabled) async {
    if (_videoPreviewEnabled == enabled || isRecording) return;
    _videoPreviewEnabled = enabled;
    await _applyPhotoCaptureAspectRatio();
    if (isInitialized) await reinitializeCurrentCamera();
  }

  /// Change flash mode
  Future<void> setFlashMode(FlashMode mode) async {
    _flashMode = mode;
    await PreferencesService.saveFlashMode(mode);
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setFlashMode(mode);
      } catch (e) {
        debugPrint("Could not set flash mode: $e");
      }
    }
  }

  Future<void> setExposureOffset(double offset) async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        final clamped = offset.clamp(_minExposure, _maxExposure);
        await _controller!.setExposureOffset(clamped);
        _currentExposure = clamped;
      } catch (e) {
        debugPrint("Exposure offset error: $e");
      }
    }
  }

  Future<void> setExposureMode(ExposureMode mode) async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setExposureMode(mode);
      } catch (e) {
        debugPrint("Exposure mode error: $e");
      }
    }
  }

  Future<void> setExposurePoint(Offset point) async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setExposurePoint(point);
      } catch (e) {
        debugPrint("Error setting exposure point: $e");
      }
    }
  }

  Future<void> setFocusPoint(Offset point) async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        await _controller!.setFocusPoint(point);
      } catch (e) {
        debugPrint("Error setting focus point: $e");
      }
    }
  }

  /// Take a photo
  Future<XFile?> takePicture() async {
    if (!isInitialized || isRecording) return null;
    final mirrorHorizontally = _isFrontCamera;
    try {
      final file = await _controller!.takePicture();
      final processed = await PhotoProcessingService.instance.process(
        file,
        targetAspectRatio: _aspectRatio,
        saveToGallery: false,
        mirrorHorizontally: mirrorHorizontally,
      );
      return processed.success ? XFile(processed.path) : null;
    } catch (e) {
      debugPrint('Error taking picture: $e');
      return null;
    }
  }

  /// Takes a raw photo from the camera without aspect ratio cropping
  Future<XFile?> takeRawPictureOnly() async {
    if (!isInitialized || isRecording) return null;
    try {
      return await _controller!.takePicture();
    } catch (e) {
      debugPrint('Error taking raw picture: $e');
      return null;
    }
  }

  Future<void> startVideoRecording() async {
    if (!isInitialized || isRecording) return;
    await _controller!.startVideoRecording();
  }

  Future<void> setRecordingOrientation(DeviceOrientation? orientation) async {
    _recordingOrientation = orientation;
    if (!isInitialized) return;
    if (orientation == null) {
      await _controller!.unlockCaptureOrientation();
    } else {
      await _controller!.lockCaptureOrientation(orientation);
    }
  }

  Future<void> startVideoRecordingWithMicrophone(String? microphoneId) async {
    if (!isInitialized || isRecording) return;

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod<void>('configureVideoRecording', {
        'preset': _resolutionPreset.name,
        'allowStillCapture': false,
      });
      await _channel.invokeMethod<void>('setRecordingMicrophone', {
        'deviceId': microphoneId,
      });
    }

    await _controller!.startVideoRecording();

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (true) {
        final started =
            await _channel.invokeMethod<bool>('isVideoRecordingStarted') ??
            false;
        if (started) break;
        if (_controller!.value.hasError || DateTime.now().isAfter(deadline)) {
          throw CameraException(
            'videoRecordingFailed',
            _controller!.value.errorDescription ??
                'Could not start the recording session.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      String? routedMicrophoneId;
      if (microphoneId != null) {
        for (var attempt = 0; attempt < 20; attempt++) {
          routedMicrophoneId = await _channel.invokeMethod<String?>(
            'getRoutedRecordingMicrophone',
          );
          if (routedMicrophoneId == 'unsupported' ||
              routedMicrophoneId == microphoneId) {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      if (microphoneId != null &&
          routedMicrophoneId != 'unsupported' &&
          routedMicrophoneId != microphoneId) {
        final failedRecording = await _controller!.stopVideoRecording();
        await File(failedRecording.path).delete();
        throw CameraException(
          'microphoneRoutingFailed',
          'Could not route audio to the selected microphone.',
        );
      }
    }
  }

  Future<double> getRecordingAmplitudeDb() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return -50;
    return await _channel.invokeMethod<double>('getRecordingAmplitudeDb') ??
        -50;
  }

  Future<XFile?> stopVideoRecording() async {
    if (_controller == null || !isRecording) return null;
    final controller = _controller!;
    try {
      return await controller.stopVideoRecording();
    } finally {
      if (identical(_controller, controller) &&
          controller.value.isRecordingVideo) {
        controller.value = controller.value.copyWith(isRecordingVideo: false);
      }
    }
  }

  Future<void> pauseVideoRecording() async {
    if (isInitialized && isRecording) {
      try {
        await _controller!.pauseVideoRecording();
      } catch (e) {
        debugPrint('Error pausing video recording: $e');
      }
    }
  }

  Future<void> resumeVideoRecording() async {
    if (isInitialized && isRecording) {
      try {
        await _controller!.resumeVideoRecording();
      } catch (e) {
        debugPrint('Error resuming video recording: $e');
      }
    }
  }

  Future<void> resumePreview() async {
    if (isInitialized) {
      try {
        await _controller!.resumePreview();
      } catch (e) {
        debugPrint('Error resuming preview: $e');
      }
    }
  }

  Future<void> pausePreview() async {
    if (isInitialized) {
      try {
        await _controller!.pausePreview();
      } catch (e) {
        debugPrint('Error pausing preview: $e');
      }
    }
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
  }

  Future<void> release() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
