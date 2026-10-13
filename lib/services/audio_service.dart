import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'preferences_service.dart';

class AudioService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  AudioSession? _session;
  StreamSubscription<Amplitude>? _amplitudeSub;
  List<InputDevice> _devices = [];
  InputDevice? _selectedDevice;
  String? _currentRecordingPath;
  bool _isMonitoring = false;
  Future<void>? _monitoringStartInProgress;
  Future<void>? _monitoringStopInProgress;

  // Amplitude history for bar waveform visualization
  static const int maxAmplitudeHistory = 40;
  final ListQueue<double> _amplitudeHistory = ListQueue<double>();

  // Stream to broadcast amplitude values for UI visualization
  final StreamController<List<double>> _amplitudeController =
      StreamController<List<double>>.broadcast();
  Stream<List<double>> get amplitudeStream => _amplitudeController.stream;

  // Also keep the raw amplitude stream for recording
  final StreamController<Amplitude> _rawAmplitudeController =
      StreamController<Amplitude>.broadcast();
  Stream<Amplitude> get rawAmplitudeStream => _rawAmplitudeController.stream;

  List<InputDevice> get devices => _devices;
  InputDevice? get selectedDevice => _selectedDevice;
  String? get currentRecordingPath => _currentRecordingPath;
  bool get isMonitoring => _isMonitoring;
  List<double> get amplitudeHistory => _amplitudeHistory.toList();

  Future<void> initialize() async {
    try {
      _session = await AudioSession.instance;
      await _session!.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.mixWithOthers |
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.videoRecording,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
        ),
      );
      debugPrint("AudioSession configured (not activated yet).");
    } catch (e) {
      debugPrint("Error configuring AudioSession: $e");
    }

    if (await _audioRecorder.hasPermission()) {
      _devices = await _audioRecorder.listInputDevices();
      if (_devices.isNotEmpty) {
        final savedMic = await PreferencesService.loadSelectedMicrophone();
        _selectedDevice = resolvePreferredDevice(
          devices: _devices,
          savedId: savedMic['id'],
          savedLabel: savedMic['label'],
        );
      }
    }
    // Initialize amplitude history with silence
    for (int i = 0; i < maxAmplitudeHistory; i++) {
      _amplitudeHistory.add(-50.0);
    }
  }

  Future<void> selectDevice(InputDevice device) async {
    final shouldRestartMonitoring = _isMonitoring;
    if (shouldRestartMonitoring) {
      await stopMonitoring();
    }
    _selectedDevice = device;
    await PreferencesService.saveSelectedMicrophone(device.id, device.label);
    if (shouldRestartMonitoring) {
      await startMonitoring();
    }
  }

  @visibleForTesting
  static InputDevice? resolvePreferredDevice({
    required List<InputDevice> devices,
    String? savedId,
    String? savedLabel,
  }) {
    if (devices.isEmpty) return null;

    if (savedId != null) {
      for (final device in devices) {
        if (device.id == savedId) return device;
      }
    }
    if (savedLabel != null) {
      for (final device in devices) {
        if (device.label == savedLabel) return device;
      }
    }
    return devices.first;
  }

  /// Start monitoring microphone amplitude WITHOUT recording
  /// Used for waveform visualization when not recording
  Future<void> startMonitoring() {
    final current = _monitoringStartInProgress;
    if (current != null) return current;
    final start = _startMonitoring().whenComplete(
      () => _monitoringStartInProgress = null,
    );
    _monitoringStartInProgress = start;
    return start;
  }

  Future<void> _startMonitoring() async {
    await _monitoringStopInProgress;
    if (_isMonitoring) return;
    if (!await _audioRecorder.hasPermission()) return;

    final Directory tempDir = await getTemporaryDirectory();
    final monitorPath =
        '${tempDir.path}/monitor_${DateTime.now().millisecondsSinceEpoch}.m4a';

    RecordConfig config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 32000,
      sampleRate: 22050,
      device: _selectedDevice,
      audioInterruption: AudioInterruptionMode.none,
    );

    await _audioRecorder.start(config, path: monitorPath);
    _isMonitoring = true;

    _amplitudeSub = _audioRecorder
        .onAmplitudeChanged(const Duration(milliseconds: 80))
        .listen((amp) {
          _addAmplitude(amp.current);
          _rawAmplitudeController.add(amp);
        });
  }

  /// Stop monitoring
  Future<void> stopMonitoring() {
    final current = _monitoringStopInProgress;
    if (current != null) return current;
    final stop = _stopMonitoring().whenComplete(
      () => _monitoringStopInProgress = null,
    );
    _monitoringStopInProgress = stop;
    return stop;
  }

  Future<void> _stopMonitoring() async {
    await _monitoringStartInProgress;
    if (!_isMonitoring) return;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _isMonitoring = false;

    try {
      final path = await _audioRecorder.stop();
      // Delete the monitor file - we don't need it
      if (path != null) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _addAmplitude(double amp) {
    _amplitudeHistory.add(amp);
    while (_amplitudeHistory.length > maxAmplitudeHistory) {
      _amplitudeHistory.removeFirst();
    }
    _amplitudeController.add(_amplitudeHistory.toList());
  }

  void addNativeAmplitude(double amplitudeDb) {
    _addAmplitude(amplitudeDb);
    _rawAmplitudeController.add(
      Amplitude(current: amplitudeDb, max: amplitudeDb),
    );
  }

  Future<void> startRecording() async {
    if (_isMonitoring) {
      await stopMonitoring();
    }

    if (await _audioRecorder.hasPermission()) {
      final Directory tempDir = await getTemporaryDirectory();
      _currentRecordingPath =
          '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      RecordConfig config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        device: _selectedDevice,
        audioInterruption: AudioInterruptionMode.none,
      );

      await _audioRecorder.start(config, path: _currentRecordingPath!);

      _amplitudeSub = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
            _addAmplitude(amp.current);
            _rawAmplitudeController.add(amp);
          });
    }
  }

  Future<String?> stopRecording() async {
    _amplitudeSub?.cancel();
    _amplitudeSub = null;

    final path = await _audioRecorder.stop();
    return path;
  }

  Future<void> pauseRecording() async {
    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.pause();
      }
    } catch (e) {
      debugPrint('Error pausing audio recording: $e');
    }
  }

  Future<void> resumeRecording() async {
    try {
      if (await _audioRecorder.isRecording()) {
        await _audioRecorder.resume();
      }
    } catch (e) {
      debugPrint('Error resuming audio recording: $e');
    }
  }

  void dispose() {
    _amplitudeSub?.cancel();
    _amplitudeController.close();
    _rawAmplitudeController.close();
    _audioRecorder.dispose();
  }
}
