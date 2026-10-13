import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/media_location.dart';
import '../models/gallery_item.dart';
import '../services/background_media_processing_service.dart';
import '../services/dual_camera_service.dart';
import '../theme/app_theme.dart';
import '../widgets/camera_controls.dart';

class DualCameraStrings {
  static const title = 'DUAL CAMERA';
  static const quality = '720p · Front + rear';
  static const initializing = 'Preparing both cameras...';
  static const swap = 'Swap the main and inset views';
  static const start = 'Start dual-camera recording';
  static const stop = 'Stop dual-camera recording';
  static const retry = 'Tekrar dene';
  static const saved = 'Dual-camera video saved.';
  static const saveFailed = 'Video kaydedilemedi.';
  static const rearMain = 'Rear camera main view';
  static const frontMain = 'Front camera main view';
  static const description =
      'The front and rear cameras are recorded together in one video.';
  static String dimensions(DualCameraPreview preview) =>
      '${preview.width.toInt()} × ${preview.height.toInt()} · Front + rear';
}

class DualCameraScreen extends StatefulWidget {
  const DualCameraScreen({
    super.key,
    this.microphoneId,
    this.locationForCapture,
    this.service,
    this.aspectRatio = 16 / 9,
    this.resolutionPreset = ResolutionPreset.high,
    this.initialOrientation = DeviceOrientation.portraitUp,
  });

  final String? microphoneId;
  final Future<MediaLocation?> Function()? locationForCapture;
  final DualCameraService? service;
  final double aspectRatio;
  final ResolutionPreset resolutionPreset;
  final DeviceOrientation initialOrientation;

  @override
  State<DualCameraScreen> createState() => _DualCameraScreenState();
}

class _DualCameraScreenState extends State<DualCameraScreen>
    with WidgetsBindingObserver {
  late final DualCameraService _service = widget.service ?? DualCameraService();
  DualCameraPreview? _preview;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<DeviceOrientation>? _orientationSubscription;
  late DeviceOrientation _orientation = widget.initialOrientation;
  Future<void> _configurationWork = Future<void>.value();
  Timer? _timer;
  bool _initializing = true;
  bool _busy = false;
  bool _recording = false;
  bool _frontIsMain = false;
  bool _closing = false;
  int _seconds = 0;
  String? _error;
  MediaLocation? _location;
  Future<void>? _lifecycleWork;
  Future<void>? _recordingOperation;
  int _initializationId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errorSubscription = _service.errors.listen(
      _handleCameraError,
      onError: (Object error) {
        _handleCameraError(_message(error));
      },
    );
    _orientationSubscription = _service.orientations.listen((orientation) {
      _orientation = orientation;
      if (!_recording && !_busy && !_initializing && _preview != null) {
        _queueConfiguration();
      }
    }, onError: (Object error) => _handleCameraError(_message(error)));
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_closing) return;
    final initializationId = ++_initializationId;
    setState(() {
      _initializing = true;
      _error = null;
      _preview = null;
    });
    try {
      final preview = await _service.initialize(
        aspectRatio: widget.aspectRatio,
        resolutionPreset: widget.resolutionPreset,
        orientation: _orientation,
      );
      if (!mounted || _closing || initializationId != _initializationId) return;
      setState(() {
        _preview = preview;
        _initializing = false;
      });
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
        await WidgetsBinding.instance.endOfFrame;
      }
      if (mounted && !_closing && initializationId == _initializationId) {
        _queueConfiguration();
        await _configurationWork;
        await _service.swap(frontIsMain: _frontIsMain);
      }
    } catch (error) {
      if (mounted && !_closing && initializationId == _initializationId) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && !_closing && initializationId == _initializationId) {
        setState(() => _initializing = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lifecycleWork = _suspend();
    } else if (state == AppLifecycleState.resumed && _lifecycleWork != null) {
      unawaited(_resume());
    }
  }

  Future<void> _suspend() async {
    _initializationId++;
    await _configurationWork;
    await _recordingOperation;
    if (_recording) await _stopRecording();
    await _service.dispose();
    if (mounted) setState(() => _preview = null);
  }

  Future<void> _resume() async {
    await _lifecycleWork;
    _lifecycleWork = null;
    if (mounted && !_closing) await _initialize();
  }

  void _handleCameraError(String message) {
    _timer?.cancel();
    unawaited(WakelockPlus.disable());
    if (mounted && !_closing) {
      setState(() {
        _error = message;
        _preview = null;
        _recording = false;
      });
    }
  }

  void _queueConfiguration() {
    _configurationWork = _configurationWork
        .then((_) async {
          if (!mounted || _closing || _recording || _preview == null) return;
          final preview = await _service.configure(
            aspectRatio: widget.aspectRatio,
            resolutionPreset: widget.resolutionPreset,
            orientation: _orientation,
          );
          if (mounted && !_closing) setState(() => _preview = preview);
        })
        .catchError((Object error) {
          _handleCameraError(_message(error));
        });
  }

  Future<void> _swap() async {
    if (_busy || _preview == null) return;
    setState(() => _busy = true);
    try {
      final next = !_frontIsMain;
      await _service.swap(frontIsMain: next);
      if (mounted) setState(() => _frontIsMain = next);
    } catch (error) {
      _showMessage(_message(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startRecording() async {
    final operation = _startRecordingInternal();
    _recordingOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_recordingOperation, operation)) _recordingOperation = null;
    }
  }

  Future<void> _startRecordingInternal() async {
    if (_busy || _recording || _preview == null) return;
    setState(() => _busy = true);
    try {
      _location = await widget.locationForCapture?.call();
      _queueConfiguration();
      await _configurationWork;
      if (_preview == null || _closing) return;
      await _service.startRecording(microphoneId: widget.microphoneId);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _seconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
      unawaited(WakelockPlus.enable());
    } catch (error) {
      _showMessage(_message(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopRecording() async {
    final operation = _stopRecordingInternal();
    _recordingOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_recordingOperation, operation)) _recordingOperation = null;
    }
  }

  Future<void> _stopRecordingInternal() async {
    if (!_recording || _busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    try {
      final path = await _service.stopRecording();
      if (mounted) setState(() => _recording = false);
      if (path != null) {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        await BackgroundMediaProcessingService.enqueueVideo(
          id: id,
          videoPaths: [path],
          resolutionPreset: ResolutionPreset.high,
          location: _location,
        );
        unawaited(_finishSaving(id));
      }
    } catch (error) {
      if (mounted) setState(() => _recording = false);
      _showMessage(_message(error), isError: true);
    } finally {
      _location = null;
      unawaited(WakelockPlus.disable());
      if (mounted) setState(() => _busy = false);
      if (!_closing && _preview != null) {
        _queueConfiguration();
        await _configurationWork;
      }
    }
  }

  Future<void> _finishSaving(String id) async {
    try {
      final item = await BackgroundMediaProcessingService.runJob(id);
      if (item?.status == GalleryItemStatus.success) {
        _showMessage(DualCameraStrings.saved);
      } else {
        _showMessage(
          item?.errorMessage ?? DualCameraStrings.saveFailed,
          isError: true,
        );
      }
    } catch (error) {
      _showMessage(_message(error), isError: true);
    }
  }

  Future<void> _close() async {
    if (_closing || _busy) return;
    _closing = true;
    _initializationId++;
    await _configurationWork;
    if (_recording) await _stopRecording();
    await _service.dispose();
    if (mounted) Navigator.of(context).pop();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted || _closing) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  static String _message(Object error) => error is PlatformException
      ? error.message ?? error.code
      : error.toString();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_errorSubscription?.cancel());
    unawaited(_orientationSubscription?.cancel());
    if (!_closing) unawaited(_service.dispose());
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final duration =
        '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: _busy ? null : _close,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text(DualCameraStrings.title),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  preview == null
                      ? DualCameraStrings.quality
                      : DualCameraStrings.dimensions(preview),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewfinder = DualCameraViewfinder(
                preview: preview,
                initializing: _initializing,
                error: _error,
                onRetry: _initialize,
              );
              final controls = DualCameraControls(
                status: _recording
                    ? duration
                    : (_frontIsMain
                          ? DualCameraStrings.frontMain
                          : DualCameraStrings.rearMain),
                recording: _recording,
                busy: _busy,
                enabled: preview != null,
                onSwap: _swap,
                onCapture: _recording ? _stopRecording : _startRecording,
              );
              if (constraints.maxWidth > constraints.maxHeight) {
                return Row(
                  spacing: 16,
                  children: [
                    Expanded(child: viewfinder),
                    SizedBox(
                      width: DualCameraControls.landscapeWidth,
                      child: controls,
                    ),
                  ],
                );
              }
              return Column(
                spacing: 16,
                children: [
                  Expanded(child: viewfinder),
                  controls,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class DualCameraViewfinder extends StatelessWidget {
  const DualCameraViewfinder({
    super.key,
    required this.preview,
    required this.initializing,
    required this.error,
    required this.onRetry,
  });
  final DualCameraPreview? preview;
  final bool initializing;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final frame = preview;
    return Center(
      child: initializing
          ? const DualCameraLoading()
          : error != null
          ? DualCameraError(message: error!, onRetry: onRetry)
          : frame == null
          ? const SizedBox.shrink()
          : AspectRatio(
              aspectRatio: frame.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radius),
                child: Texture(
                  key: const Key('dual_camera_preview'),
                  textureId: frame.textureId,
                ),
              ),
            ),
    );
  }
}

class DualCameraControls extends StatelessWidget {
  const DualCameraControls({
    super.key,
    required this.status,
    required this.recording,
    required this.busy,
    required this.enabled,
    required this.onSwap,
    required this.onCapture,
  });
  static const landscapeWidth = 250.0;
  final String status;
  final bool recording;
  final bool busy;
  final bool enabled;
  final VoidCallback onSwap;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        Text(
          status,
          key: const Key('dual_camera_status'),
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CameraControlButton(
              key: const Key('dual_camera_swap'),
              icon: Icons.cameraswitch,
              onPressed: busy || !enabled ? null : onSwap,
              tooltip: DualCameraStrings.swap,
            ),
            Semantics(
              button: true,
              label: recording
                  ? DualCameraStrings.stop
                  : DualCameraStrings.start,
              child: IconButton.filled(
                key: const Key('dual_camera_capture'),
                onPressed: busy || !enabled ? null : onCapture,
                style: IconButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                  fixedSize: const Size.square(72),
                ),
                icon: busy
                    ? const CircularProgressIndicator()
                    : Icon(
                        recording ? Icons.stop : Icons.fiber_manual_record,
                        size: 36,
                      ),
              ),
            ),
            const SizedBox.square(dimension: 44),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
          child: Text(
            DualCameraStrings.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class DualCameraLoading extends StatelessWidget {
  const DualCameraLoading({super.key});
  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    spacing: 16,
    children: [
      CircularProgressIndicator(),
      Text(DualCameraStrings.initializing),
    ],
  );
}

class DualCameraError extends StatelessWidget {
  const DualCameraError({
    super.key,
    required this.message,
    required this.onRetry,
  });
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        const Icon(Icons.videocam_off_outlined, size: 40),
        Text(message, textAlign: TextAlign.center),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text(DualCameraStrings.retry),
        ),
      ],
    ),
  );
}
