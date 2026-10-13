export '../models/capture_mode.dart';

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/capture_mode.dart';
import '../models/capture_geometry.dart';
import '../models/media_location.dart';
import '../services/camera_service.dart';
import '../services/audio_service.dart';
import '../services/background_media_processing_service.dart';
import '../services/location_metadata_service.dart';
import '../services/preferences_service.dart';
import '../widgets/audio_level_panel.dart';
import '../widgets/camera_controls.dart';
import '../theme/app_theme.dart';
import '../services/camera_intent_service.dart';
import '../services/photo_processing_service.dart';
import '../services/media_muxer_service.dart';
import '../widgets/camera_settings_sheet.dart';
import '../widgets/camera_lens_selector.dart';
import '../widgets/camera_preview_guard.dart';
import '../widgets/capture_flash_overlay.dart';
import '../widgets/capture_resolution_badge.dart';
import '../widgets/photo_capture_flight.dart';
import '../widgets/manual_camera_controls.dart';
import 'gallery_screen.dart';
import 'dual_camera_screen.dart';
import 'timeburst_settings_dialog.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, this.launchRequest});
  final CameraLaunchRequest? launchRequest;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final CameraService _cameraService = CameraService();
  final AudioService _audioService = AudioService();
  static const _landscapeControlsWidth = 300.0;
  static const _viewfinderTopInset = 64.0;
  static const _controlMargin = 16.0;

  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isLockScreenMode = false;
  bool _isSwitchingCamera = false;
  bool _isCameraPreviewSuspended = false;
  bool _isDualCameraOpen = false;
  bool _isChangingRecordingState = false;
  bool _isManualMode = false;
  ManualCameraSetting _selectedManualSetting = ManualCameraSetting.iso;
  bool _isAudioWaveformVisible = true;
  bool _showCaptureFlash = false;
  bool _isLocationMetadataEnabled = false;
  bool _isResolvingLocation = false;
  bool _isChangingCaptureMode = false;
  bool _stopRecordingRequested = false;
  MediaLocation? _captureLocation;
  MediaLocation? _activeRecordingLocation;
  double? _activeVideoAspectRatio;
  int _isoValue = 400;
  int _shutterValue = 20000000; // 20ms in nanoseconds (1/50s)
  double _focusValue = 0.0; // Infinity by default (0.0 diopters)
  CaptureMode _captureMode = CaptureMode.photo;
  bool get _returnsCapture => widget.launchRequest?.returnCapture ?? false;

  // Video segments recorded during single video session
  final List<String> _recordedVideoSegments = [];

  // Timeburst state
  TimeburstSettings _timeburstSettings = TimeburstSettings(
    intervalSeconds: 1.0,
    totalDurationSeconds: 10,
  );
  int _timeburstPhotosCaptured = 0;
  final List<String> _timeburstImagePaths = [];
  Future<void>? _timeburstCaptureInFlight;

  // Gallery items captured during session
  final ValueNotifier<List<GalleryItem>> _galleryItemsNotifier =
      ValueNotifier<List<GalleryItem>>([]);
  final GlobalKey _cameraPreviewKey = GlobalKey();
  final GlobalKey _galleryButtonKey = GlobalKey();
  OverlayEntry? _captureFlightEntry;
  Timer? _galleryRefreshTimer;
  bool _isRefreshingGallery = false;

  // Animation for the record button pulsing
  late AnimationController _pulseController;

  // Recording timer
  Timer? _recordingTimer;
  Timer? _nativeAmplitudeTimer;
  bool _isReadingNativeAmplitude = false;
  int _recordingSeconds = 0;

  // Zoom by drag state
  bool _isZooming = false;
  double _dragStartZoom = 1.0;
  double _dragCurrentOffsetX = 0.0;

  // Focus & Exposure variables
  Offset? _tapFocusOffset;
  bool _showFocusIndicator = false;
  Timer? _focusIndicatorTimer;

  double _exposureSliderVal = 0.0;
  Timer? _exposureSliderFadeTimer;
  bool _showExposureSlider = false;

  double get _overlayBottom {
    const baseOffset = 220.0;
    const lensSelectorHeight = 48.0;
    return baseOffset +
        (!_cameraService.isFrontCamera &&
                _cameraService.backLensInfos.length > 1
            ? lensSelectorHeight
            : 0);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _initializeServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDualCameraOpen) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (state == AppLifecycleState.paused && _isRecording) {
        // Android revokes camera access when the activity stays in the background.
        // Finalize the file before that happens instead of losing the recording.
        unawaited(
          _captureMode == CaptureMode.timeburst
              ? _stopTimeburst()
              : _stopRecording(),
        );
      }
      if (!_isRecording) {
        _cameraService.pausePreview();
        if (_captureMode == CaptureMode.video && _isAudioWaveformVisible) {
          _audioService.stopMonitoring();
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_isRecording) {
        _resumeFromBackground();
        if (_captureMode == CaptureMode.video && _isAudioWaveformVisible) {
          _audioService.startMonitoring();
        }
      } else {
        _cameraService.resumePreview();
      }
      unawaited(_refreshProcessingItems());
      unawaited(_recoverPendingJobs());
    }
  }

  Future<void> _resumeFromBackground() async {
    if (_cameraService.isInitialized) {
      await _cameraService.resumePreview();
    } else {
      await _reinitializeCamera();
    }
  }

  Future<void> _reinitializeCamera() async {
    setState(() => _isInitializing = true);
    try {
      await _cameraService.reinitializeCurrentCamera();
    } catch (e) {
      debugPrint("Camera restart failed: $e");
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _initializeServices() async {
    try {
      debugPrint("=== INIT: Loading saved preferences ===");
      final savedMode = await PreferencesService.loadCaptureMode();
      final isAudioWaveformVisible =
          await PreferencesService.loadAudioWaveformVisible();
      final savedItems = await PreferencesService.loadGalleryItems();

      if (mounted) {
        setState(() {
          _captureMode = widget.launchRequest?.mode ?? savedMode;
          _isAudioWaveformVisible = isAudioWaveformVisible;
        });
        _galleryItemsNotifier.value = savedItems;
      }
      // A worker can be stopped while FFmpeg is running. Pick up durable
      // jobs in the foreground as soon as the app opens again.
      unawaited(_recoverPendingJobs());
      _galleryRefreshTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_refreshProcessingItems()),
      );

      debugPrint("=== INIT: Starting camera initialize ===");
      await _cameraService.initialize(
        videoPreviewEnabled: _captureMode == CaptureMode.video,
      );
      if (widget.launchRequest?.lowVideoQuality ?? false) {
        await _cameraService.setResolution(
          ResolutionPreset.medium,
          persist: false,
        );
      }
      debugPrint("=== INIT: Camera initialized ===");
      await _audioService.initialize();
      debugPrint("=== INIT: Audio initialized ===");
      if (_captureMode == CaptureMode.video && _isAudioWaveformVisible) {
        await _audioService.startMonitoring();
      }
    } catch (e) {
      debugPrint("Service startup failed: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        debugPrint("=== INIT: isInitializing = false ===");
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    _nativeAmplitudeTimer?.cancel();
    _galleryRefreshTimer?.cancel();
    _captureFlightEntry?.remove();
    _pulseController.dispose();
    _cameraService.dispose();
    _audioService.stopMonitoring();
    _audioService.dispose();
    WakelockPlus.disable();
    _galleryItemsNotifier.dispose();
    _focusIndicatorTimer?.cancel();
    _exposureSliderFadeTimer?.cancel();
    super.dispose();
  }

  // ─── Photo ───────────────────────────────────────────────
  Future<void> _takePicture() async {
    if (_isProcessing ||
        _isChangingCaptureMode ||
        _isRecording ||
        _isSwitchingCamera ||
        _isChangingRecordingState ||
        !_cameraService.isInitialized) {
      return;
    }

    unawaited(HapticFeedback.mediumImpact());
    setState(() => _isProcessing = true);

    final aspectRatio = _cameraService.aspectRatio;
    final mirrorHorizontally = _cameraService.isFrontCamera;
    try {
      final location = await _locationForCapture();
      final rawFile = await _cameraService.takeRawPictureOnly();
      if (rawFile != null) {
        unawaited(_playCaptureFlash());
      }
      if (rawFile == null) {
        throw StateError('The camera did not produce a photo.');
      }

      if (_returnsCapture) {
        final processed = await PhotoProcessingService.instance.process(
          rawFile,
          targetAspectRatio: aspectRatio,
          saveToGallery: false,
          mirrorHorizontally: mirrorHorizontally,
        );
        if (!processed.success) {
          throw StateError('Could not prepare the photo.');
        }
        await CameraIntentService.complete(processed.path);
        return;
      }

      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final enqueued = await BackgroundMediaProcessingService.enqueuePhoto(
        id: id,
        sourcePath: rawFile.path,
        targetAspectRatio: aspectRatio,
        mirrorHorizontally: mirrorHorizontally,
        location: location,
      );
      _addGalleryItem(enqueued.item);
      unawaited(
        _finishProcessingJob(
          id,
          fallbackMessage: 'An error occurred while processing the photo.',
          showPhotoCaptureFlight: true,
        ),
      );
    } catch (error) {
      debugPrint('Error in _takePicture: $error');
      if (mounted) setState(() => _isProcessing = false);
      _showBackgroundNotification(
        'Could not take photo: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _toggleLocationMetadata() async {
    if (_isRecording || _isChangingRecordingState || _isResolvingLocation) {
      return;
    }

    if (_isLocationMetadataEnabled) {
      setState(() {
        _isLocationMetadataEnabled = false;
        _captureLocation = null;
      });
      _showBackgroundNotification('Location metadata disabled', isError: false);
      return;
    }

    setState(() => _isResolvingLocation = true);
    try {
      final location = await LocationMetadataService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _isLocationMetadataEnabled = true;
        _captureLocation = location;
      });
      _showBackgroundNotification('Location metadata enabled', isError: false);
    } catch (error) {
      debugPrint('Location metadata could not be enabled: $error');
      _showBackgroundNotification(
        'Could not get location: $error',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isResolvingLocation = false);
    }
  }

  Future<MediaLocation?> _locationForCapture() async {
    if (!_isLocationMetadataEnabled) return null;

    try {
      final location = await LocationMetadataService.getCurrentLocation();
      if (mounted) setState(() => _captureLocation = location);
      return location;
    } catch (error) {
      debugPrint('Fresh capture location unavailable: $error');
      return _captureLocation;
    }
  }

  Future<void> _playCaptureFlash() async {
    if (!mounted) return;
    setState(() => _showCaptureFlash = true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (mounted) setState(() => _showCaptureFlash = false);
  }

  void _showPhotoCaptureFlight(String imagePath) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final previewBox =
          _cameraPreviewKey.currentContext?.findRenderObject() as RenderBox?;
      final galleryBox =
          _galleryButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final overlay = Overlay.of(context);
      if (previewBox == null || galleryBox == null) return;

      final previewOrigin = previewBox.localToGlobal(Offset.zero);
      final galleryOrigin = galleryBox.localToGlobal(Offset.zero);
      final begin = previewOrigin & previewBox.size;
      final end = galleryOrigin & galleryBox.size;

      _captureFlightEntry?.remove();
      late final OverlayEntry entry;
      entry = OverlayEntry(
        builder: (context) => PhotoCaptureFlight(
          imagePath: imagePath,
          begin: begin,
          end: end,
          onCompleted: () {
            entry.remove();
            if (identical(_captureFlightEntry, entry)) {
              _captureFlightEntry = null;
            }
          },
        ),
      );
      _captureFlightEntry = entry;
      overlay.insert(entry);
    });
  }

  // ─── Video Recording ─────────────────────────────────────
  Future<void> _startRecording() async {
    if (_isChangingCaptureMode ||
        _isProcessing ||
        _isChangingRecordingState ||
        _isSwitchingCamera ||
        _isRecording ||
        !_cameraService.isInitialized) {
      return;
    }
    _isChangingRecordingState = true;
    _stopRecordingRequested = false;
    unawaited(HapticFeedback.lightImpact());
    try {
      _activeRecordingLocation = await _locationForCapture();
      if (!mounted || _stopRecordingRequested) return;
      final orientation = _cameraService.controller!.value.deviceOrientation;
      _activeVideoAspectRatio = CaptureGeometry.orientedAspectRatio(
        _cameraService.aspectRatio,
        orientation,
      );
      await _cameraService.setRecordingOrientation(orientation);
      if (_captureMode != CaptureMode.video) {
        setState(() => _isCameraPreviewSuspended = true);
        await WidgetsBinding.instance.endOfFrame;
        await _cameraService.setVideoPreviewEnabled(true);
        await _restoreCameraPreviewAfterSwitch();
      }
      _recordedVideoSegments.clear();
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (Platform.isAndroid) {
        await _audioService.stopMonitoring();
        await _cameraService.startVideoRecordingWithMicrophone(
          _audioService.selectedDevice?.id,
        );
        _startNativeAmplitudeMonitoring();
      } else {
        await Future.wait<void>([
          _cameraService.startVideoRecording(),
          _audioService.startRecording(),
        ]);
      }
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          if (!_isSwitchingCamera && !_cameraService.isInitialized) {
            unawaited(_stopRecording());
            return;
          }
          setState(() => _recordingSeconds++);
          final limit = widget.launchRequest?.durationLimitSeconds ?? 0;
          if (_returnsCapture && limit > 0 && _recordingSeconds >= limit) {
            unawaited(_stopRecording());
          }
        }
      });
      unawaited(WakelockPlus.enable());
    } catch (error) {
      debugPrint('Video recording could not start: $error');
      _nativeAmplitudeTimer?.cancel();
      _nativeAmplitudeTimer = null;
      try {
        if (_cameraService.isRecording) {
          await _cameraService.stopVideoRecording();
        }
        if (!Platform.isAndroid) await _audioService.stopRecording();
      } catch (cleanupError) {
        debugPrint('Failed to clean up recording: $cleanupError');
      }
      _activeRecordingLocation = null;
      unawaited(WakelockPlus.disable());
      _recordingTimer?.cancel();
      if (mounted) {
        setState(() => _isRecording = false);
      }
      _showBackgroundNotification(
        'Could not start video recording: $error',
        isError: true,
      );
      if (Platform.isAndroid && _isAudioWaveformVisible) {
        unawaited(_restartAudioMonitoringAfterCameraSettles());
      }
    } finally {
      if (!_isRecording) await _releaseRecordingGeometry();
      if (mounted) {
        setState(() => _isChangingRecordingState = false);
      } else {
        _isChangingRecordingState = false;
      }
      if (_stopRecordingRequested && _isRecording && mounted) {
        _stopRecordingRequested = false;
        await _stopRecording();
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_isChangingRecordingState || _isSwitchingCamera) {
      _stopRecordingRequested = true;
      return;
    }
    if (!_isRecording) {
      return;
    }
    _isChangingRecordingState = true;
    unawaited(HapticFeedback.lightImpact());
    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _isProcessing = false;
      _isLockScreenMode = false;
    });
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      await WidgetsBinding.instance.endOfFrame;
    }
    unawaited(WakelockPlus.disable());
    _nativeAmplitudeTimer?.cancel();
    _nativeAmplitudeTimer = null;

    String? audioPath;
    try {
      XFile? lastSegment;
      try {
        if (Platform.isAndroid) {
          lastSegment = await _cameraService.stopVideoRecording();
        } else {
          final stopped = await Future.wait<Object?>([
            _cameraService.stopVideoRecording(),
            _audioService.stopRecording(),
          ]);
          lastSegment = stopped[0] as XFile?;
          audioPath = stopped[1] as String?;
        }
        if (lastSegment != null) {
          _recordedVideoSegments.add(lastSegment.path);
        }
      } catch (error) {
        _showBackgroundNotification(
          'Could not save the final video segment: $error',
          isError: true,
        );
      }
      if (!_returnsCapture &&
          _captureMode == CaptureMode.video &&
          _isAudioWaveformVisible) {
        unawaited(_restartAudioMonitoringAfterCameraSettles());
      }

      if (_recordedVideoSegments.isNotEmpty &&
          (Platform.isAndroid || audioPath != null)) {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        if (_returnsCapture) {
          final output = '${_recordedVideoSegments.last}.returned.mp4';
          final video = await MediaMuxerService.finalizeVideoSegments(
            videoPaths: List.of(_recordedVideoSegments),
            outputPath: output,
            resolutionPreset: _cameraService.resolutionPreset,
            targetAspectRatio: _activeVideoAspectRatio,
            location: _activeRecordingLocation,
          );
          if (video == null) throw StateError('Could not prepare the video.');
          await CameraIntentService.complete(video);
          for (final path in _recordedVideoSegments) {
            final segment = File(path);
            if (await segment.exists()) await segment.delete();
          }
          return;
        }
        final enqueued = await BackgroundMediaProcessingService.enqueueVideo(
          id: id,
          videoPaths: List<String>.from(_recordedVideoSegments),
          audioPath: audioPath,
          resolutionPreset: _cameraService.resolutionPreset,
          targetAspectRatio: _activeVideoAspectRatio,
          location: _activeRecordingLocation,
        );
        _addGalleryItem(enqueued.item);
        unawaited(
          _finishProcessingJob(
            id,
            fallbackMessage: 'An error occurred while processing the video.',
          ),
        );
      }
    } catch (error) {
      debugPrint('Video recording could not stop cleanly: $error');
      _showBackgroundNotification(
        'Could not finish video recording: $error',
        isError: true,
      );
    } finally {
      _activeRecordingLocation = null;
      await _releaseRecordingGeometry();
      _stopRecordingRequested = false;
      if (mounted) {
        setState(() => _isChangingRecordingState = false);
      } else {
        _isChangingRecordingState = false;
      }
    }
  }

  Future<void> _releaseRecordingGeometry() async {
    _activeVideoAspectRatio = null;
    try {
      await _cameraService.setRecordingOrientation(null);
      if (mounted && _captureMode != CaptureMode.video) {
        await _cameraService.setVideoPreviewEnabled(false);
      }
    } catch (error) {
      debugPrint('Capture geometry could not be restored: $error');
    } finally {
      if (mounted) setState(() => _isCameraPreviewSuspended = false);
    }
  }

  void _startNativeAmplitudeMonitoring() {
    _nativeAmplitudeTimer?.cancel();
    _nativeAmplitudeTimer = Timer.periodic(const Duration(milliseconds: 80), (
      timer,
    ) async {
      if (_isReadingNativeAmplitude || !_isRecording) return;
      _isReadingNativeAmplitude = true;
      try {
        final amplitudeDb = await _cameraService.getRecordingAmplitudeDb();
        if (mounted && _isRecording) {
          _audioService.addNativeAmplitude(amplitudeDb);
        }
      } catch (error) {
        debugPrint('Could not read recording audio level: $error');
      } finally {
        _isReadingNativeAmplitude = false;
      }
    });
  }

  Future<void> _restartAudioMonitoringAfterCameraSettles() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (mounted &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
        !_isRecording &&
        _captureMode == CaptureMode.video &&
        _isAudioWaveformVisible) {
      await _audioService.startMonitoring();
    }
  }

  // ─── Timeburst ───────────────────────────────────────────
  Future<void> _startTimeburst() async {
    if (_isChangingCaptureMode ||
        _isRecording ||
        _isProcessing ||
        _isChangingRecordingState ||
        _isSwitchingCamera ||
        !_cameraService.isInitialized) {
      return;
    }
    _isChangingRecordingState = true;
    unawaited(HapticFeedback.mediumImpact());
    try {
      _activeRecordingLocation = await _locationForCapture();
      if (!mounted) return;
      _timeburstImagePaths.clear();
      setState(() {
        _isRecording = true;
        _timeburstPhotosCaptured = 0;
        _recordingSeconds = 0;
      });
      unawaited(WakelockPlus.enable());
      final intervalMs = (_timeburstSettings.intervalSeconds * 1000).round();
      _recordingTimer = Timer.periodic(Duration(milliseconds: intervalMs), (
        timer,
      ) async {
        if (mounted) {
          setState(() => _recordingSeconds = (timer.tick * intervalMs) ~/ 1000);
        }
        if (_timeburstCaptureInFlight != null ||
            _isSwitchingCamera ||
            !_isRecording) {
          return;
        }
        final capture = _captureTimeburstPhoto();
        _timeburstCaptureInFlight = capture;
        try {
          await capture;
        } finally {
          _timeburstCaptureInFlight = null;
        }
        final total = _timeburstSettings.totalPhotos;
        if (total != -1 && _timeburstPhotosCaptured >= total) {
          await _stopTimeburst();
        }
      });
    } catch (error) {
      _activeRecordingLocation = null;
      _showBackgroundNotification(
        'Could not start timeburst: $error',
        isError: true,
      );
    } finally {
      _isChangingRecordingState = false;
    }
  }

  Future<void> _captureTimeburstPhoto() async {
    try {
      final file = await _cameraService.takePicture();
      if (file == null) return;
      _timeburstImagePaths.add(file.path);
      if (mounted) setState(() => _timeburstPhotosCaptured++);
    } catch (error) {
      debugPrint('Timeburst photo capture failed: $error');
    }
  }

  Future<void> _stopTimeburst() async {
    if (!_isRecording || _isChangingRecordingState) return;
    _isChangingRecordingState = true;
    _recordingTimer?.cancel();
    unawaited(HapticFeedback.mediumImpact());
    try {
      // A shutter request cannot be cancelled. Include its result before moving inputs.
      await _timeburstCaptureInFlight;
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isLockScreenMode = false;
        });
      }
      if (_timeburstImagePaths.isNotEmpty) {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        final enqueued =
            await BackgroundMediaProcessingService.enqueueTimeburst(
              id: id,
              imagePaths: List<String>.from(_timeburstImagePaths),
              resolutionPreset: _cameraService.resolutionPreset,
              location: _activeRecordingLocation,
            );
        _timeburstImagePaths.clear();
        _addGalleryItem(enqueued.item);
        unawaited(
          _finishProcessingJob(
            id,
            fallbackMessage:
                'An error occurred while processing the timeburst.',
          ),
        );
      }
    } catch (error) {
      _showBackgroundNotification(
        'Timeburst kaydedilemedi: $error',
        isError: true,
      );
    } finally {
      _activeRecordingLocation = null;
      _isChangingRecordingState = false;
      unawaited(WakelockPlus.disable());
    }
  }

  void _addGalleryItem(GalleryItem item) {
    if (!mounted) return;
    final items = List<GalleryItem>.from(_galleryItemsNotifier.value);
    final existingIndex = items.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (existingIndex == -1) {
      items.add(item);
    } else {
      items[existingIndex] = item;
    }
    _galleryItemsNotifier.value = items;
  }

  void _replaceGalleryItem(GalleryItem item) {
    if (!mounted) return;
    final currentItems = List<GalleryItem>.from(_galleryItemsNotifier.value);
    final index = currentItems.indexWhere(
      (candidate) => candidate.id == item.id,
    );
    if (index != -1) {
      currentItems[index] = item;
      _galleryItemsNotifier.value = currentItems;
    }
  }

  Future<void> _finishProcessingJob(
    String id, {
    required String fallbackMessage,
    bool showPhotoCaptureFlight = false,
  }) async {
    final item = await BackgroundMediaProcessingService.runJob(id);
    if (!mounted || item == null) return;
    _replaceGalleryItem(item);
    if (showPhotoCaptureFlight && item.status == GalleryItemStatus.success) {
      _showPhotoCaptureFlight(item.path);
    }
    if (item.status == GalleryItemStatus.failed) {
      _showBackgroundNotification(
        item.errorMessage ?? fallbackMessage,
        isError: true,
      );
    }
  }

  Future<void> _recoverPendingJobs() async {
    try {
      await BackgroundMediaProcessingService.recoverPendingJobs();
      await _refreshProcessingItems();
    } catch (error, stackTrace) {
      debugPrint('Pending media recovery failed: $error\n$stackTrace');
    }
  }

  Future<void> _refreshProcessingItems() async {
    if (_isRefreshingGallery) {
      return;
    }
    _isRefreshingGallery = true;
    try {
      final savedItems = await PreferencesService.loadGalleryItems();
      if (!mounted) return;
      final savedById = <String, GalleryItem>{
        for (final item in savedItems) item.id: item,
      };
      final previousItems = _galleryItemsNotifier.value;
      final merged = <GalleryItem>[
        for (final item in previousItems) savedById[item.id] ?? item,
        for (final item in savedItems)
          if (!previousItems.any((previous) => previous.id == item.id)) item,
      ];
      final hasChanges =
          merged.length != previousItems.length ||
          merged.any((next) {
            final previous = previousItems.firstWhere(
              (item) => item.id == next.id,
              orElse: () => next,
            );
            return previous.status != next.status ||
                previous.path != next.path ||
                previous.thumbnailPath != next.thumbnailPath ||
                previous.errorMessage != next.errorMessage;
          });
      if (hasChanges) {
        _galleryItemsNotifier.value = merged;
      }
    } finally {
      _isRefreshingGallery = false;
    }
  }

  void _showBackgroundNotification(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _toggleLockScreen() {
    setState(() {
      _isLockScreenMode = !_isLockScreenMode;
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _applyZoomFromDrag(double dx) {
    final maxZoom = _cameraService.maxZoom;
    final minZoom = _cameraService.minZoom;
    final zoomRange = maxZoom - minZoom;

    // Reach maximum zoom with an approximately 200-pixel drag.
    final zoomDelta = (dx / 200.0) * zoomRange;
    double newZoom = _dragStartZoom + zoomDelta;
    newZoom = newZoom.clamp(minZoom, maxZoom);

    _cameraService.setZoom(newZoom);
    setState(() {}); // Update the zoom interface.
  }

  void _handleTapToFocus(
    TapUpDetails details,
    BoxConstraints constraints,
  ) async {
    final x = details.localPosition.dx / constraints.maxWidth;
    final y = details.localPosition.dy / constraints.maxHeight;
    final focusPoint = Offset(x, y);

    await _cameraService.setFocusPoint(focusPoint);
    await _cameraService.setExposureMode(ExposureMode.auto);
    await _cameraService.setExposureOffset(0.0);
    await _cameraService.setExposurePoint(focusPoint);

    setState(() {
      _tapFocusOffset = details.localPosition;
      _showFocusIndicator = true;
      _showExposureSlider = false;
      _exposureSliderVal = 0.0;
    });

    _focusIndicatorTimer?.cancel();
    _focusIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showFocusIndicator = false;
        });
      }
    });
  }

  Future<void> _handleCameraSwitch(CameraDescription camera) async {
    if (_isSwitchingCamera ||
        _isChangingRecordingState ||
        _isProcessing ||
        _timeburstCaptureInFlight != null) {
      return;
    }
    try {
      setState(() {
        _isSwitchingCamera = true;
        _isCameraPreviewSuspended = true;
      });

      if (_isRecording && _captureMode != CaptureMode.timeburst) {
        final previousCamera = _cameraService.controller?.description;
        final segment = await _cameraService.stopVideoRecording();
        if (segment != null) {
          _recordedVideoSegments.add(segment.path);
        }
        try {
          await _cameraService.switchCamera(camera);
          await _resumeRecordingAfterCameraSwitch();
        } catch (error, stackTrace) {
          // Opening a lens can succeed even when its recording session fails.
          // Restore the working camera and keep the completed video segments.
          try {
            if (mounted && previousCamera != null) {
              setState(() => _isCameraPreviewSuspended = true);
              await _cameraService.switchCamera(previousCamera);
              await _resumeRecordingAfterCameraSwitch();
            }
          } catch (restoreError) {
            debugPrint('Video recording could not be restored: $restoreError');
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
      } else {
        await _cameraService.switchCamera(camera);
      }

      if (_isManualMode) {
        await _cameraService.setManualISO(_isoValue);
        await _cameraService.setManualShutter(_shutterValue);
      }
      _focusValue = _cameraService.manualFocusDistance ?? 0;
    } catch (e) {
      debugPrint("Could not switch cameras: $e");
      if (_isRecording &&
          _captureMode != CaptureMode.timeburst &&
          !_cameraService.isRecording) {
        _isSwitchingCamera = false;
        await _stopRecording();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Could not switch cameras: $e"),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingCamera = false;
          _isCameraPreviewSuspended = false;
        });
        if (_stopRecordingRequested &&
            _isRecording &&
            _captureMode != CaptureMode.timeburst) {
          _stopRecordingRequested = false;
          await _stopRecording();
        }
      }
    }
  }

  Future<void> _resumeRecordingAfterCameraSwitch() async {
    await _restoreCameraPreviewAfterSwitch();
    if (!mounted) return;
    if (Platform.isAndroid) {
      await _cameraService.startVideoRecordingWithMicrophone(
        _audioService.selectedDevice?.id,
      );
      _startNativeAmplitudeMonitoring();
    } else {
      await _cameraService.startVideoRecording();
    }
  }

  Future<void> _restoreCameraPreviewAfterSwitch() async {
    if (!mounted) return;
    setState(() => _isCameraPreviewSuspended = false);
    // Mount the new texture before replacing its preview session with recording.
    // Otherwise undrained preview buffers can make Camera2 time out on Android.
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    if (lifecycleState == null || lifecycleState == AppLifecycleState.resumed) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _switchCameraFacing() async {
    final candidates = _cameraService.isFrontCamera
        ? _cameraService.backCameras
        : _cameraService.frontCameras;
    if (candidates.isEmpty) return;
    final index = _cameraService.isFrontCamera
        ? _cameraService.currentBackCameraIndex
        : 0;
    await _handleCameraSwitch(candidates[index]);
  }

  void _openGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GalleryScreen(itemsNotifier: _galleryItemsNotifier),
      ),
    );
  }

  Future<void> _setManualFocus(double value) async {
    try {
      await _cameraService.setManualFocus(value);
      if (mounted) {
        setState(() => _focusValue = _cameraService.manualFocusDistance ?? 0);
      }
    } catch (error) {
      debugPrint('Manual focus failed: $error');
      _showBackgroundNotification(
        ManualCameraStrings.focusFailed,
        isError: true,
      );
    }
  }

  void _showMicrophonePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              Text(
                "SELECT MICROPHONE",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _audioService.devices.length,
                  itemBuilder: (context, index) {
                    final device = _audioService.devices[index];
                    final isSelected =
                        _audioService.selectedDevice?.id == device.id;
                    return ListTile(
                      leading: Icon(
                        Icons.mic,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      title: Text(
                        device.label,
                        style: TextStyle(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : null,
                      onTap: _isRecording
                          ? null
                          : () async {
                              await _audioService.selectDevice(device);
                              if (!context.mounted) return;
                              setState(() {});
                              Navigator.pop(context);
                            },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── BUILD ───────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    // Lock screen mode UI
    if (_isLockScreenMode) {
      return GestureDetector(
        onDoubleTap: _toggleLockScreen,
        child: Scaffold(
          backgroundColor: AppTheme.background,
          body: Center(
            child: Text(
              "Double tap to open",
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                fontSize: 16,
              ),
            ),
          ),
        ),
      );
    }

    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final safePadding = MediaQuery.paddingOf(context);
    final audioHeight =
        _captureMode == CaptureMode.video && _isAudioWaveformVisible
        ? AudioLevelPanel.height *
              (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(1.0, 1.5)
        : 0.0;
    final viewfinderPadding = landscape
        ? EdgeInsets.fromLTRB(
            _controlMargin,
            safePadding.top + _viewfinderTopInset,
            _landscapeControlsWidth + _controlMargin + safePadding.right,
            safePadding.bottom +
                _controlMargin +
                (_isManualMode ? ManualCameraControls.height : 0),
          )
        : EdgeInsets.only(
            top: safePadding.top + _viewfinderTopInset,
            bottom:
                _overlayBottom +
                (_isManualMode ? ManualCameraControls.height : audioHeight) +
                _controlMargin +
                safePadding.bottom,
          );
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview with correct aspect ratio
          if (_cameraService.controller != null && !_isCameraPreviewSuspended)
            Padding(
              padding: viewfinderPadding,
              child: KeyedSubtree(
                key: _cameraPreviewKey,
                child: CameraPreviewGuard(
                  controller: _cameraService.controller!,
                  onRecover: () async {
                    if (_isRecording) await _stopRecording();
                    if (_cameraService.backCameras.isNotEmpty) {
                      await _handleCameraSwitch(
                        _cameraService.backCameras.first,
                      );
                    }
                  },
                  child: _buildCameraPreview(),
                ),
              ),
            ),

          // 2. Audio Waveform Overlay - visible when manual controls are NOT open and in video mode
          if (!_isManualMode &&
              _captureMode == CaptureMode.video &&
              _isAudioWaveformVisible)
            Positioned(
              bottom: _overlayBottom,
              left: landscape ? null : 16,
              right: 16,
              width: landscape
                  ? _landscapeControlsWidth - _controlMargin
                  : null,
              child: StreamBuilder<List<double>>(
                stream: _audioService.amplitudeStream,
                builder: (context, snapshot) {
                  final amplitudes =
                      snapshot.data ?? _audioService.amplitudeHistory;
                  return AudioLevelPanel(
                    compact: landscape,
                    amplitudes: amplitudes,
                    isRecording: _isRecording,
                    microphoneLabel:
                        _audioService.selectedDevice?.label ??
                        'Default microphone',
                    onMicrophoneTap: _isRecording
                        ? null
                        : _showMicrophonePicker,
                    onVisibilityToggle: _toggleAudioWaveform,
                  );
                },
              ),
            ),
          if (!_isManualMode &&
              _captureMode == CaptureMode.video &&
              !_isAudioWaveformVisible)
            Positioned(
              bottom: _overlayBottom,
              left: landscape ? null : 16,
              right: landscape ? 16 : null,
              child: _AudioWaveformRestoreButton(
                onPressed: _toggleAudioWaveform,
              ),
            ),

          // 3. Top Controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: _buildTopControls(),
          ),

          // 4. Recording timer or Timeburst progress
          if (_isRecording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _captureMode == CaptureMode.timeburst
                            ? 'Timeburst: $_timeburstPhotosCaptured / ${_timeburstSettings.totalPhotos == -1 ? '∞' : _timeburstSettings.totalPhotos} (${_formatDuration(_recordingSeconds)})'
                            : _formatDuration(_recordingSeconds),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Camera switching overlay.
          if (_isSwitchingCamera)
            Positioned.fill(
              child: Container(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.7),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: [
                      CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      Text(
                        "Switching cameras...",
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 5b. Manual Controls Panel
          if (_isManualMode)
            Positioned(
              bottom: landscape
                  ? safePadding.bottom + _controlMargin
                  : _overlayBottom,
              left: _controlMargin,
              right: landscape
                  ? _landscapeControlsWidth + _controlMargin + safePadding.right
                  : _controlMargin,
              child: ManualCameraControls(
                key: const Key('manual_controls'),
                selected: _selectedManualSetting,
                iso: _isoValue,
                shutterNanos: _shutterValue,
                focusDistance: _focusValue,
                maximumFocusDistance: _cameraService.maximumFocusDistance,
                enabled:
                    !_isProcessing &&
                    !_isSwitchingCamera &&
                    !_isChangingCaptureMode &&
                    !_isChangingRecordingState,
                onSelected: (setting) =>
                    setState(() => _selectedManualSetting = setting),
                onIsoChanged: (value) {
                  setState(() => _isoValue = value);
                  unawaited(_cameraService.setManualISO(value));
                },
                onShutterChanged: (value) {
                  setState(() => _shutterValue = value);
                  unawaited(_cameraService.setManualShutter(value));
                },
                onFocusChanged: (value) => unawaited(_setManualFocus(value)),
                onAuto: () async {
                  await _cameraService.setAutoMode();
                  if (mounted) {
                    setState(() {
                      _isManualMode = false;
                      _focusValue = 0;
                    });
                  }
                },
              ),
            ),

          // 5c. Timeburst Controls Panel
          if (_captureMode == CaptureMode.timeburst && !_isRecording)
            Positioned(
              bottom: _overlayBottom,
              left: 16,
              right: 16,
              child: _buildTimeburstControlPanel(),
            ),

          // 6. Bottom Controls
          Positioned(
            key: const ValueKey('bottom_controls'),
            bottom: 0,
            left: landscape ? null : 0,
            right: 0,
            width: landscape ? _landscapeControlsWidth : null,
            child: _buildBottomControls(),
          ),

          // 7. Zoom indicator during drag
          if (_isZooming || _cameraService.currentZoom > _cameraService.minZoom)
            Positioned(
              bottom: 180,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    "${_cameraService.currentZoom.toStringAsFixed(1)}x",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),

          Positioned.fill(
            child: CaptureFlashOverlay(
              key: const Key('capture_flash_overlay'),
              visible: _showCaptureFlash,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraService.controller!;
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final orientation = value.isRecordingVideo
            ? value.recordingOrientation ?? value.deviceOrientation
            : value.lockedCaptureOrientation ?? value.deviceOrientation;
        final cameraAspectRatio = CaptureGeometry.orientedAspectRatio(
          value.aspectRatio,
          orientation,
        );
        final targetAspectRatio =
            _activeVideoAspectRatio ??
            CaptureGeometry.orientedAspectRatio(
              _cameraService.aspectRatio,
              orientation,
            );
        final sourceSize = value.previewSize!;
        final landscape = CaptureGeometry.isLandscape(orientation);
        final outputSize = CaptureGeometry.videoSize(
          (landscape ? sourceSize.width : sourceSize.height).round(),
          (landscape ? sourceSize.height : sourceSize.width).round(),
          targetAspectRatio,
          _cameraService.resolutionPreset,
        );
        return Container(
          color: AppTheme.background,
          alignment: Alignment.center,
          child: AspectRatio(
            key: const Key('camera_viewfinder_frame'),
            aspectRatio: targetAspectRatio,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapUp: (details) => _handleTapToFocus(details, constraints),
                  onVerticalDragStart: (details) {
                    _exposureSliderFadeTimer?.cancel();
                    setState(() {
                      _showExposureSlider = true;
                    });
                    _cameraService.setExposureMode(ExposureMode.locked);
                  },
                  onVerticalDragUpdate: (details) {
                    final range =
                        _cameraService.maxExposure - _cameraService.minExposure;
                    final change = -(details.delta.dy / 200.0) * range;
                    final newVal = (_cameraService.currentExposure + change)
                        .clamp(
                          _cameraService.minExposure,
                          _cameraService.maxExposure,
                        );
                    _cameraService.setExposureOffset(newVal);
                    setState(() {
                      _exposureSliderVal = newVal;
                    });
                  },
                  onVerticalDragEnd: (details) {
                    _exposureSliderFadeTimer = Timer(
                      const Duration(seconds: 2),
                      () {
                        if (mounted) {
                          setState(() => _showExposureSlider = false);
                        }
                      },
                    );
                  },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        child: OverflowBox(
                          alignment: Alignment.center,
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              height: constraints.maxWidth / cameraAspectRatio,
                              child: CameraPreview(controller),
                            ),
                          ),
                        ),
                      ),

                      // Visual Focus Indicator Overlay
                      if (_captureMode == CaptureMode.video || _isRecording)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CaptureResolutionBadge(
                            width: outputSize.width,
                            height: outputSize.height,
                          ),
                        ),
                      if (_showFocusIndicator && _tapFocusOffset != null)
                        Positioned(
                          left: _tapFocusOffset!.dx - 25,
                          top: _tapFocusOffset!.dy - 25,
                          child: const FocusIndicatorWidget(),
                        ),

                      // Visual Brightness Slider Overlay
                      if (_showExposureSlider)
                        Positioned(
                          right: 16,
                          top: constraints.maxHeight / 2 - 100,
                          child: SizedBox(
                            height: 200,
                            child: BrightnessSliderWidget(
                              value: _exposureSliderVal,
                              min: _cameraService.minExposure,
                              max: _cameraService.maxExposure,
                              onChanged: (newVal) {
                                _cameraService.setExposureOffset(newVal);
                                setState(() {
                                  _exposureSliderVal = newVal;
                                });
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopControls() {
    final controlSpacing = MediaQuery.sizeOf(context).width < 360 ? 4.0 : 8.0;
    if (_isRecording) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCircleButton(
            icon: _isLockScreenMode ? Icons.lock : Icons.lock_outline,
            onTap: _toggleLockScreen,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left side: 3 popups (Resolution, Aspect Ratio, Flash) side-by-side
        Row(
          spacing: controlSpacing,
          children: [
            _buildResolutionSelector(),
            _buildAspectRatioSelector(),
            _buildFlashSelector(),
          ],
        ),

        // Right side: Location and camera switch buttons
        Row(
          spacing: controlSpacing,
          children: [
            _buildLocationButton(),
            if (!_returnsCapture)
              CameraControlButton(
                key: const Key('camera_settings_button'),
                icon: Icons.settings_outlined,
                tooltip: 'Camera settings',
                onPressed: _isProcessing ? null : _showSettings,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppBarCircleButton({IconData? icon, Widget? content}) =>
      CameraControlSurface(
        child:
            content ?? (icon == null ? const SizedBox() : Icon(icon, size: 20)),
      );

  Widget _buildResolutionSelector() {
    final currentPreset = _cameraService.resolutionPreset;

    final labels = {
      ResolutionPreset.low: '240p',
      ResolutionPreset.medium: '480p',
      ResolutionPreset.high: '720p',
      ResolutionPreset.veryHigh: '1080p',
      ResolutionPreset.ultraHigh: '4K',
      ResolutionPreset.max: 'Maks',
    };

    final label = labels[currentPreset] ?? 'Maks';

    return Theme(
      data: Theme.of(
        context,
      ).copyWith(cardColor: Theme.of(context).colorScheme.surface),
      child: PopupMenuButton<ResolutionPreset>(
        enabled:
            !_isRecording &&
            !_isChangingRecordingState &&
            !_isChangingCaptureMode &&
            !_isSwitchingCamera,
        initialValue: currentPreset,
        offset: const Offset(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: _buildAppBarCircleButton(
          content: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onSelected: (preset) async {
          setState(() => _isInitializing = true);
          try {
            await WidgetsBinding.instance.endOfFrame;
            await _cameraService.setResolution(preset);
          } finally {
            if (mounted) setState(() => _isInitializing = false);
          }
        },
        itemBuilder: (context) => ResolutionPreset.values.map((preset) {
          final isSelected = preset == currentPreset;
          return PopupMenuItem<ResolutionPreset>(
            value: preset,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  labels[preset] ?? preset.name,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                    size: 16,
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAspectRatioSelector() {
    final currentRatio = _cameraService.aspectRatio;

    final labels = {4 / 3: '4:3', 16 / 9: '16:9', 1.0: '1:1'};

    final currentEntry = labels.entries.firstWhere(
      (entry) => (entry.key - currentRatio).abs() < 0.01,
      orElse: () => labels.entries.first,
    );

    return Theme(
      data: Theme.of(
        context,
      ).copyWith(cardColor: Theme.of(context).colorScheme.surface),
      child: PopupMenuButton<double>(
        enabled:
            !_isRecording &&
            !_isChangingRecordingState &&
            !_isChangingCaptureMode &&
            !_isSwitchingCamera,
        initialValue: currentEntry.key,
        offset: const Offset(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: _buildAppBarCircleButton(
          content: Text(
            currentEntry.value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onSelected: (ratio) async {
          setState(() => _isInitializing = true);
          try {
            await WidgetsBinding.instance.endOfFrame;
            await _cameraService.setAspectRatio(ratio);
          } finally {
            if (mounted) setState(() => _isInitializing = false);
          }
        },
        itemBuilder: (context) => labels.entries.map((entry) {
          final isSelected = (entry.key - currentRatio).abs() < 0.01;
          return PopupMenuItem<double>(
            value: entry.key,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  entry.value,
                  style: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                    size: 16,
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFlashSelector() {
    final currentFlash = _cameraService.flashMode;

    final icons = {
      FlashMode.off: Icons.flash_off,
      FlashMode.auto: Icons.flash_auto,
      FlashMode.always: Icons.flash_on,
      FlashMode.torch: Icons.flashlight_on,
    };

    final labels = {
      FlashMode.off: 'Off',
      FlashMode.auto: 'Otomatik',
      FlashMode.always: 'On',
      FlashMode.torch: 'Fener',
    };

    return Theme(
      data: Theme.of(
        context,
      ).copyWith(cardColor: Theme.of(context).colorScheme.surface),
      child: PopupMenuButton<FlashMode>(
        initialValue: currentFlash,
        offset: const Offset(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: _buildAppBarCircleButton(
          icon: icons[currentFlash] ?? Icons.flash_off,
        ),
        onSelected: (mode) async {
          await _cameraService.setFlashMode(mode);
          setState(() {});
        },
        itemBuilder: (context) => FlashMode.values.map((mode) {
          final isSelected = mode == currentFlash;
          return PopupMenuItem<FlashMode>(
            value: mode,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  spacing: 8,
                  children: [
                    Icon(
                      icons[mode] ?? Icons.flash_off,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 18,
                    ),
                    Text(
                      labels[mode] ?? mode.name,
                      style: TextStyle(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (isSelected)
                  Icon(
                    Icons.check,
                    color: Theme.of(context).colorScheme.primary,
                    size: 16,
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLocationButton() {
    final enabled = _isLocationMetadataEnabled;
    return _buildCircleButton(
      icon: _isResolvingLocation
          ? Icons.hourglass_top_rounded
          : (enabled ? Icons.location_on : Icons.location_off_outlined),
      onTap: _isRecording || _isChangingRecordingState
          ? null
          : _toggleLocationMetadata,
      color: enabled ? Theme.of(context).colorScheme.primary : null,
      tooltip: enabled
          ? 'Disable location metadata'
          : 'Add location to photos and videos',
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    VoidCallback? onTap,
    Color? color,
    String? tooltip,
  }) {
    return CameraControlButton(
      icon: icon,
      onPressed: onTap,
      tooltip: tooltip,
      color: color,
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        top: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppTheme.background.withValues(alpha: 0.9),
            AppTheme.background.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mode selector (Photo / Video)
          if (!_isRecording && !_returnsCapture) _buildModeSelector(),

          const SizedBox(height: 12),

          // Lens Selection (always visible)
          if (!_cameraService.isFrontCamera)
            CameraLensSelector(
              lenses: _cameraService.backLensInfos,
              selectedCameraId: _cameraService.currentCameraId,
              enabled:
                  !_isProcessing &&
                  !_isSwitchingCamera &&
                  !_isChangingRecordingState,
              onSelected: _handleCameraSwitch,
            ),

          const SizedBox(height: 16),

          Row(
            key: const ValueKey('capture_controls'),
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Gallery button
                    GestureDetector(
                      key: _galleryButtonKey,
                      onTap: _isRecording
                          ? null
                          : (_returnsCapture
                                ? CameraIntentService.cancel
                                : _openGallery),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.26),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: _returnsCapture
                              ? const Icon(Icons.close_rounded)
                              : ValueListenableBuilder<List<GalleryItem>>(
                                  valueListenable: _galleryItemsNotifier,
                                  builder: (context, items, _) {
                                    if (items.isNotEmpty) {
                                      final item = items.last;
                                      return Hero(
                                        tag: galleryHeroTag(item.id),
                                        child: _buildGalleryThumbnail(item),
                                      );
                                    }
                                    return Icon(
                                      Icons.photo_library,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                          .withValues(alpha: 0.54),
                                      size: 24,
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                    // Settings or Manual Controls Button
                    if (_captureMode == CaptureMode.timeburst)
                      const SizedBox(width: 48)
                    else
                      IconButton(
                        icon: Icon(
                          _isManualMode ? Icons.tune : Icons.tune_outlined,
                          color: _isManualMode
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                          size: 28,
                        ),
                        onPressed: () {
                          setState(() {
                            _isManualMode = !_isManualMode;
                          });
                        },
                        tooltip: 'Manual settings',
                      ),
                  ],
                ),
              ),
              _buildCaptureButton(),
              Expanded(
                child: Center(
                  child: CameraControlButton(
                    key: Key(
                      _isRecording
                          ? 'recording_camera_switch_button'
                          : 'camera_switch_button',
                    ),
                    icon: Icons.cameraswitch_rounded,
                    tooltip: ManualCameraStrings.cameraSwitch,
                    onPressed:
                        _isProcessing ||
                            _isSwitchingCamera ||
                            _isChangingCaptureMode ||
                            _isChangingRecordingState ||
                            !_cameraService.isInitialized ||
                            _cameraService.frontCameras.isEmpty ||
                            _cameraService.backCameras.isEmpty ||
                            (_isRecording &&
                                _captureMode == CaptureMode.timeburst)
                        ? null
                        : _switchCameraFacing,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryThumbnail(GalleryItem item) {
    if (item.status == GalleryItemStatus.processing) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.all(12),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (item.status == GalleryItemStatus.failed) {
      return Container(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Icon(
          Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          size: 20,
        ),
      );
    }
    if (item.thumbnailPath != null && File(item.thumbnailPath!).existsSync()) {
      return Image.file(
        File(item.thumbnailPath!),
        fit: BoxFit.cover,
        width: 48,
        height: 48,
      );
    } else if (item.isPhoto && File(item.path).existsSync()) {
      return Image.file(
        File(item.path),
        fit: BoxFit.cover,
        width: 48,
        height: 48,
      );
    } else {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          item.isPhoto ? Icons.photo : Icons.videocam,
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.54),
          size: 24,
        ),
      );
    }
  }

  Future<void> _changeCaptureMode(CaptureMode mode) async {
    if (_captureMode == mode ||
        _isRecording ||
        _isProcessing ||
        _isChangingCaptureMode ||
        _isChangingRecordingState ||
        _isSwitchingCamera) {
      return;
    }
    final previousMode = _captureMode;
    if (mode == CaptureMode.dualVideo) {
      await _openDualCamera();
      return;
    }
    setState(() {
      _isChangingCaptureMode = true;
      _captureMode = mode;
    });
    try {
      setState(() => _isCameraPreviewSuspended = true);
      await WidgetsBinding.instance.endOfFrame;
      await _cameraService.setVideoPreviewEnabled(mode == CaptureMode.video);
      await _restoreCameraPreviewAfterSwitch();
      if (previousMode == CaptureMode.video) {
        await _audioService.stopMonitoring();
      }
      if (mode == CaptureMode.video && _isAudioWaveformVisible) {
        await _audioService.startMonitoring();
      }
      if (widget.launchRequest == null) {
        await PreferencesService.saveCaptureMode(mode);
      }
    } catch (error) {
      _showBackgroundNotification(
        'Could not change capture mode: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChangingCaptureMode = false;
          _isCameraPreviewSuspended = false;
        });
      }
    }
  }

  Future<void> _toggleAudioWaveform() async {
    final shouldShow = !_isAudioWaveformVisible;
    setState(() => _isAudioWaveformVisible = shouldShow);
    await PreferencesService.saveAudioWaveformVisible(shouldShow);

    if (!_isRecording && _captureMode == CaptureMode.video) {
      if (shouldShow) {
        await _audioService.startMonitoring();
      } else {
        await _audioService.stopMonitoring();
      }
    }
  }

  Future<void> _openDualCamera() async {
    final orientation =
        _cameraService.controller?.value.deviceOrientation ??
        DeviceOrientation.portraitUp;
    setState(() {
      _isChangingCaptureMode = true;
      _isCameraPreviewSuspended = true;
      _isDualCameraOpen = true;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      await _audioService.stopMonitoring();
      await _cameraService.release();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DualCameraScreen(
            microphoneId: _audioService.selectedDevice?.id,
            locationForCapture: _locationForCapture,
            aspectRatio: _cameraService.aspectRatio,
            resolutionPreset: _cameraService.resolutionPreset,
            initialOrientation: orientation,
          ),
        ),
      );
    } finally {
      try {
        if (mounted) {
          await _cameraService.reinitializeCurrentCamera();
          _galleryItemsNotifier.value =
              await PreferencesService.loadGalleryItems();
          if (_captureMode == CaptureMode.video && _isAudioWaveformVisible) {
            await _audioService.startMonitoring();
          }
        }
      } catch (error) {
        _showBackgroundNotification(
          'Could not reopen the camera: $error',
          isError: true,
        );
      } finally {
        _isDualCameraOpen = false;
        if (mounted) {
          setState(() {
            _isChangingCaptureMode = false;
            _isCameraPreviewSuspended = false;
          });
        }
      }
    }
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) => CameraSettingsSheet(
          waveformVisible: _isAudioWaveformVisible,
          onToggleWaveform: () async {
            await _toggleAudioWaveform();
            if (context.mounted) updateSheet(() {});
          },
          onOpenDefaults: () async {
            Navigator.pop(sheetContext);
            try {
              await CameraIntentService.openCameraSelector();
            } catch (error) {
              _showBackgroundNotification(
                'Could not open camera selection: $error',
                isError: true,
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildModeSelector() =>
      CaptureModeSelector(mode: _captureMode, onSelected: _changeCaptureMode);

  Widget _buildCaptureButton() {
    return GestureDetector(
      key: const Key('capture_button'),
      onTap: _isRecording
          ? (_captureMode == CaptureMode.timeburst
                ? _stopTimeburst
                : _stopRecording)
          : (_captureMode == CaptureMode.photo
                ? _takePicture
                : (_captureMode == CaptureMode.timeburst
                      ? _startTimeburst
                      : _startRecording)),

      // Drag-to-zoom gestures are available in photo and video modes.
      onHorizontalDragStart: (details) {
        if (_captureMode == CaptureMode.timeburst) return;
        _dragStartZoom = _cameraService.currentZoom;
        _dragCurrentOffsetX = 0.0;
        setState(() => _isZooming = true);
      },
      onHorizontalDragUpdate: (details) {
        if (_captureMode == CaptureMode.timeburst) return;
        _dragCurrentOffsetX += details.delta.dx;
        _applyZoomFromDrag(_dragCurrentOffsetX);
      },
      onHorizontalDragEnd: (details) {
        setState(() => _isZooming = false);
      },
      onHorizontalDragCancel: () {
        setState(() => _isZooming = false);
      },

      // Hold to record video in photo mode.
      onLongPressStart: (details) {
        if (!_returnsCapture &&
            _captureMode == CaptureMode.photo &&
            !_isRecording) {
          _dragStartZoom = _cameraService.currentZoom;
          setState(() => _isZooming = true);
          _startRecording(); // Start a short video recording.
        }
      },
      onLongPressMoveUpdate: (details) {
        if (_captureMode == CaptureMode.photo && _isRecording) {
          // Allow horizontal drag-to-zoom during recording as well.
          _applyZoomFromDrag(details.offsetFromOrigin.dx);
        }
      },
      onLongPressEnd: (details) {
        if (_captureMode == CaptureMode.photo &&
            (_isRecording || _isChangingRecordingState)) {
          setState(() => _isZooming = false);
          _stopRecording(); // Stop recording when the press ends.
        }
      },
      onLongPressCancel: () {
        if (_captureMode == CaptureMode.photo &&
            (_isRecording || _isChangingRecordingState)) {
          setState(() => _isZooming = false);
          _stopRecording();
        }
      },

      child: Semantics(
        button: true,
        label: _isRecording
            ? 'Stop recording'
            : _captureMode == CaptureMode.photo
            ? 'Take photo'
            : 'Start recording',
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final isPhoto = _captureMode == CaptureMode.photo && !_isRecording;

            return Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isRecording
                      ? Theme.of(context).colorScheme.error.withValues(
                          alpha: 0.55 + 0.4 * _pulseController.value,
                        )
                      : Theme.of(context).colorScheme.onSurface,
                  width: 4,
                ),
              ),
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _isRecording ? 28 : 60,
                  height: _isRecording ? 28 : 60,
                  decoration: BoxDecoration(
                    color: isPhoto
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(_isRecording ? 8 : 30),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimeburstControlPanel() {
    final List<double> intervals = [0.5, 1.0, 2.0, 3.0, 5.0, 10.0];
    final List<int> durations = [
      60,
      300,
      600,
      900,
      1800,
      3600,
      7200,
      18000,
      36000,
      86400,
      -1,
    ];

    String formatInterval(double interval) {
      if (interval == interval.roundToDouble()) {
        return '${interval.toInt()}s';
      }
      return '${interval}s';
    }

    String formatDuration(int seconds) {
      if (seconds == -1) return 'Unlimited';
      if (seconds < 60) return '$seconds sn';
      if (seconds < 3600) {
        final m = seconds ~/ 60;
        return '$m dk';
      }
      final h = seconds ~/ 3600;
      return '$h sa';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "TIMEBURST AYARLARI",
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                "Capture interval",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: intervals.map((interval) {
                    final isSelected =
                        _timeburstSettings.intervalSeconds == interval;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(formatInterval(interval)),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _timeburstSettings = TimeburstSettings(
                                intervalSeconds: interval,
                                totalDurationSeconds:
                                    _timeburstSettings.totalDurationSeconds,
                              );
                            });
                          }
                        },
                        selectedColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                "Total duration",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: durations.map((duration) {
                    final isSelected =
                        _timeburstSettings.totalDurationSeconds == duration;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(formatDuration(duration)),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _timeburstSettings = TimeburstSettings(
                                intervalSeconds:
                                    _timeburstSettings.intervalSeconds,
                                totalDurationSeconds: duration,
                              );
                            });
                          }
                        },
                        selectedColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Theme.of(context).colorScheme.onSurface
                              : Theme.of(context).colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Custom Focus Indicator Widget ───────────────────────
class _AudioWaveformRestoreButton extends StatelessWidget {
  const _AudioWaveformRestoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(16),
      child: IconButton(
        key: const Key('audio_waveform_show_button'),
        onPressed: onPressed,
        tooltip: 'Show audio waveform',
        color: colorScheme.primary,
        icon: const Icon(Icons.graphic_eq),
      ),
    );
  }
}

class FocusIndicatorWidget extends StatefulWidget {
  const FocusIndicatorWidget({super.key});

  @override
  State<FocusIndicatorWidget> createState() => _FocusIndicatorWidgetState();
}

class _FocusIndicatorWidgetState extends State<FocusIndicatorWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.4 - (0.4 * _controller.value);
        final opacity = 1.0 - (0.3 * _controller.value);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(),
            ),
          ),
        );
      },
    );
  }
}

// ─── Custom Brightness/Exposure Slider Widget ────────────
class BrightnessSliderWidget extends StatelessWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const BrightnessSliderWidget({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final range = max - min;
    final percent = range == 0 ? 0.5 : ((value - min) / range).clamp(0.0, 1.0);

    return GestureDetector(
      onVerticalDragUpdate: (details) {
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localPos = box.globalToLocal(details.globalPosition);
        final double height = box.size.height;
        if (height > 0) {
          final double dragPercent = (1.0 - (localPos.dy / height)).clamp(
            0.0,
            1.0,
          );
          final double newValue = min + (dragPercent * range);
          onChanged(newValue);
        }
      },
      child: Container(
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.background.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wb_sunny,
              color: Theme.of(context).colorScheme.primary,
              size: 18,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: percent,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${value > 0 ? "+" : ""}${value.toStringAsFixed(1)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CameraOption {
  final String label;
  final bool isFront;
  final double zoomFactor;

  const CameraOption({
    required this.label,
    required this.isFront,
    required this.zoomFactor,
  });
}
