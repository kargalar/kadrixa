import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:camerapro/screens/camera_screen.dart';
import 'package:camerapro/services/preferences_service.dart';
import 'package:camerapro/services/camera_service.dart';
import 'package:camerapro/widgets/capture_flash_overlay.dart';
import 'package:camerapro/widgets/camera_preview_guard.dart';
import 'package:camerapro/theme/app_theme.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }

  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.path;
  }
}

class FakeCameraPlatform extends CameraPlatform {
  final List<CameraDescription> createdDescriptions = <CameraDescription>[];
  final List<ResolutionPreset?> createdPresets = [];
  final orientationEvents =
      StreamController<DeviceOrientationChangedEvent>.broadcast();
  String? picturePath;
  final Set<String> failingCameraIds = <String>{};
  final Set<String> failingVideoCameraIds = <String>{};
  Future<XFile>? pendingPhoto;
  int photoRequests = 0;
  Future<void>? pendingVideoStart;
  VoidCallback? onVideoStart;
  int videoStopRequests = 0;
  int videoStartRequests = 0;
  final errorEvents = StreamController<CameraErrorEvent>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async {
    return [
      const CameraDescription(
        name: '0',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
      const CameraDescription(
        name: '1',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 90,
      ),
    ];
  }

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    createdDescriptions.add(cameraDescription);
    createdPresets.add(resolutionPreset);
    if (failingCameraIds.contains(cameraDescription.name)) {
      throw CameraException('CameraAccess', 'Lens unavailable');
    }
    return 0; // camera id
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    return;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) {
    return Stream.value(
      const CameraInitializedEvent(
        0,
        1920.0,
        1080.0,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
  }

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() {
    return orientationEvents.stream;
  }

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}

  @override
  Future<void> unlockCaptureOrientation(int cameraId) async {}

  @override
  Stream<CameraClosingEvent> onCameraClosing(int cameraId) {
    return StreamController<CameraClosingEvent>().stream;
  }

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) {
    final generation = createdDescriptions.length;
    return errorEvents.stream.where(
      (_) => generation == createdDescriptions.length,
    );
  }

  @override
  Widget buildPreview(int cameraId) {
    return Container(width: 300, height: 400, color: Colors.black);
  }

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1.0;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 5.0;

  @override
  Future<double> getMinExposureOffset(int cameraId) async => -2.0;

  @override
  Future<double> getMaxExposureOffset(int cameraId) async => 2.0;

  @override
  Future<void> dispose(int cameraId) async {}

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {}

  @override
  Future<double> setExposureOffset(int cameraId, double offset) async => 0.0;

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {}

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {}

  @override
  Future<XFile> takePicture(int cameraId) async {
    photoRequests++;
    if (pendingPhoto != null) return pendingPhoto!;
    final path = picturePath;
    if (path == null) throw StateError('picturePath must be set by the test');
    return XFile(path);
  }

  @override
  Future<void> startVideoCapturing(VideoCaptureOptions options) async {
    videoStartRequests++;
    onVideoStart?.call();
    if (failingVideoCameraIds.contains(createdDescriptions.last.name)) {
      throw CameraException('videoRecordingFailed', 'Recording session failed');
    }
    await pendingVideoStart;
  }

  @override
  Future<XFile> stopVideoRecording(int cameraId) async {
    videoStopRequests++;
    return XFile('/test/video.mp4');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel appCamerasChannel = MethodChannel('app.kadrixa/cameras');
  const MethodChannel permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );
  const MethodChannel recordChannel = MethodChannel(
    'com.llfbandit.record/messages',
  );
  const MethodChannel galChannel = MethodChannel('gal');
  const MethodChannel audioSessionChannel = MethodChannel(
    'com.ryanheise.audio_session',
  );
  const MethodChannel avAudioSessionChannel = MethodChannel(
    'com.ryanheise.av_audio_session',
  );
  const MethodChannel androidAudioManagerChannel = MethodChannel(
    'com.ryanheise.android_audio_manager',
  );
  late FakeCameraPlatform fakeCameraPlatform;
  late List<Map<String, Object>> mockCameraMaps;
  Future<void>? pendingMonitoringStop;
  final recordEventChannels = <String>{};
  const wakelockChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

  testWidgets(
    'compact manual panel preserves preview and sends the lens focus range',
    (tester) async {
      mockCameraMaps[0] = {
        ...mockCameraMaps[0],
        'minimumFocusDistance': 4.5,
        'supportsManualFocus': true,
      };
      final focusDistances = <double>[];
      var autoCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(appCamerasChannel, (call) async {
            if (call.method == 'getAllPhysicalCameras') return mockCameraMaps;
            if (call.method == 'setManualFocus') {
              focusDistances.add(
                (call.arguments as Map)['focusDistance'] as double,
              );
            }
            if (call.method == 'setAutoMode') autoCalls++;
            return null;
          });
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Manual settings'));
      await tester.pump();
      final panel = find.byKey(const Key('manual_controls'));
      expect(tester.getSize(panel).height, 128);
      expect(
        tester
            .getRect(find.byKey(const Key('camera_viewfinder_frame')))
            .overlaps(tester.getRect(panel)),
        isFalse,
      );
      expect(find.byType(Slider), findsOneWidget);
      await tester.tap(find.byKey(const Key('manual_focus_tab')));
      await tester.pump();
      final slider = find.byKey(const Key('manual_focus_slider'));
      expect(tester.widget<Slider>(slider).max, 4.5);
      await tester.drag(slider, const Offset(180, 0));
      await tester.pump();
      expect(focusDistances, isNotEmpty);
      expect(focusDistances.last, greaterThan(0));
      expect(
        focusDistances.every((value) => value <= 4.5 && value >= 0),
        isTrue,
      );
      await tester.tap(find.byTooltip('Return to automatic settings'));
      await tester.pump();
      expect(autoCalls, 1);
      expect(panel, findsNothing);
      final flipRect = tester.getRect(
        find.byKey(const Key('camera_switch_button')),
      );
      final captureRect = tester.getRect(
        find.byKey(const Key('capture_button')),
      );
      expect(flipRect.left, greaterThan(captureRect.right));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'unsupported focus is disabled and landscape panel stays outside preview',
    (tester) async {
      tester.view.physicalSize = const Size(900, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.byTooltip('Manual settings'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('manual_focus_tab')));
      await tester.pump();
      expect(
        tester
            .widget<Slider>(find.byKey(const Key('manual_focus_slider')))
            .onChanged,
        isNull,
      );
      expect(find.text('Bu lenste manuel odak desteklenmiyor'), findsOneWidget);
      final frame = tester.getRect(
        find.byKey(const Key('camera_viewfinder_frame')),
      );
      final panel = tester.getRect(find.byKey(const Key('manual_controls')));
      expect(frame.overlaps(panel), isFalse);
      expect(panel.bottom, lessThanOrEqualTo(420));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          wakelockChannel,
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
    PreferencesService.isTestMode = true;
    PreferencesService.testData = {};
    PreferencesService.testGalleryItems = [];
    pendingMonitoringStop = null;
    PathProviderPlatform.instance = MockPathProviderPlatform();
    fakeCameraPlatform = FakeCameraPlatform();
    CameraPlatform.instance = fakeCameraPlatform;
    mockCameraMaps = <Map<String, Object>>[
      <String, Object>{'id': '0', 'lensFacing': 1, 'sensorOrientation': 90},
      <String, Object>{'id': '1', 'lensFacing': 0, 'sensorOrientation': 90},
    ];

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appCamerasChannel, (
          MethodCall methodCall,
        ) async {
          final method = methodCall.method;
          if (method == 'getAllPhysicalCameras') {
            return mockCameraMaps;
          }
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'checkPermissionStatus') {
            return 1; // PermissionStatus.granted
          }
          if (methodCall.method == 'requestPermissions') {
            final List<dynamic> requested =
                methodCall.arguments as List<dynamic>;
            final Map<dynamic, dynamic> result = {};
            for (final req in requested) {
              result[req] = 1; // granted
            }
            return result;
          }
          return 1;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (MethodCall methodCall) async {
          final method = methodCall.method;
          if (method == 'create') {
            final id = (methodCall.arguments as Map)['recorderId'];
            final name = 'com.llfbandit.record/events/$id';
            recordEventChannels.add(name);
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  MethodChannel(name),
                  (_) async => null,
                );
            return null;
          }
          if (method == 'hasPermission') return true;
          if (method == 'listInputDevices') return [];
          if (method == 'getAmplitude') {
            return <String, double>{'current': -30, 'max': -10};
          }
          if (method == 'stop') {
            await pendingMonitoringStop;
            return null;
          }
          return true;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(galChannel, (MethodCall methodCall) async {
          return true;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, (
          MethodCall methodCall,
        ) async {
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(avAudioSessionChannel, (
          MethodCall methodCall,
        ) async {
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidAudioManagerChannel, (
          MethodCall methodCall,
        ) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(wakelockChannel, null);
    for (final name in recordEventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
    recordEventChannels.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appCamerasChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(galChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(avAudioSessionChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidAudioManagerChannel, null);
  });

  group('CameraScreen Widget Tests', () {
    testWidgets('landscape controls leave the full viewfinder visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      PreferencesService.testData['captureMode'] = CaptureMode.video.name;
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      fakeCameraPlatform.orientationEvents.add(
        const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft),
      );
      await tester.pump();
      final frame = tester.getRect(
        find.byKey(const Key('camera_viewfinder_frame')),
      );
      expect(frame.width / frame.height, closeTo(4 / 3, 0.001));
      expect(
        frame.overlaps(
          tester.getRect(find.byKey(const Key('audio_level_panel'))),
        ),
        isFalse,
      );
      expect(
        frame.overlaps(tester.getRect(find.byKey(const Key('capture_button')))),
        isFalse,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('failed switched recording resumes on the previous camera', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('VIDEO'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('capture_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      fakeCameraPlatform.failingVideoCameraIds.add('1');
      await tester.tap(find.byKey(const Key('recording_camera_switch_button')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(
        fakeCameraPlatform.createdDescriptions.map((camera) => camera.name),
        ['0', '0', '1', '0'],
      );
      expect(fakeCameraPlatform.videoStopRequests, 1);
      expect(fakeCameraPlatform.videoStartRequests, 3);
      final preview = tester.widget<CameraPreviewGuard>(
        find.byType(CameraPreviewGuard),
      );
      expect(preview.controller.description.name, '0');
      expect(preview.controller.value.isRecordingVideo, isTrue);
      expect(find.text('Switching cameras...'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const Key('recording_camera_switch_button')),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('new preview is mounted before switched recording starts', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('VIDEO'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('capture_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final videoStart = Completer<void>();
      fakeCameraPlatform.pendingVideoStart = videoStart.future;
      var previewMountedAtVideoStart = false;
      fakeCameraPlatform.onVideoStart = () {
        final previewFinder = find.byType(CameraPreviewGuard);
        if (previewFinder.evaluate().isEmpty) return;
        previewMountedAtVideoStart =
            tester
                .widget<CameraPreviewGuard>(previewFinder)
                .controller
                .description
                .name ==
            '1';
      };
      await tester.tap(find.byKey(const Key('recording_camera_switch_button')));
      await tester.pump();
      await tester.pump();
      expect(fakeCameraPlatform.videoStartRequests, 2);
      expect(previewMountedAtVideoStart, isTrue);
      expect(find.text('Switching cameras...'), findsOneWidget);
      final preview = tester.widget<CameraPreviewGuard>(
        find.byType(CameraPreviewGuard),
      );
      expect(preview.controller.description.name, '1');
      expect(preview.controller.value.isInitialized, isTrue);
      expect(preview.controller.value.isRecordingVideo, isFalse);

      videoStart.complete();
      await tester.pump();
      expect(find.text('Switching cameras...'), findsNothing);
      expect(preview.controller.value.isRecordingVideo, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('front and rear cameras can switch during video recording', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('VIDEO'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('capture_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final flip = find.byKey(const Key('recording_camera_switch_button'));
      expect(flip, findsOneWidget);
      await tester.tap(flip);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(fakeCameraPlatform.createdDescriptions.last.name, '1');
      expect(fakeCameraPlatform.videoStopRequests, 1);
      expect(fakeCameraPlatform.videoStartRequests, 2);
      await tester.tap(flip);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(fakeCameraPlatform.createdDescriptions.last.name, '0');
      expect(fakeCameraPlatform.videoStopRequests, 2);
      expect(fakeCameraPlatform.videoStartRequests, 3);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('camera failure does not leave the recording timer running', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(find.text('VIDEO'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('capture_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      fakeCameraPlatform.errorEvents.add(
        CameraErrorEvent(0, 'Camera disconnected'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      expect(fakeCameraPlatform.videoStopRequests, 1);
      expect(
        find.byKey(const Key('recording_camera_switch_button')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'backgrounding finalizes video without waiting for a UI frame',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        addTearDown(() {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });
        await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.text('VIDEO'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byKey(const Key('capture_button')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(fakeCameraPlatform.videoStartRequests, 1);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        expect(fakeCameraPlatform.videoStopRequests, 1);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('camera controls fit a narrow phone with the app theme', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const CameraScreen()),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('camera_settings_button')), findsOneWidget);
      await tester.tap(find.text('VIDEO'));
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('audio_waveform_hide_button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('audio_level_panel')), findsNothing);
      await tester.tap(find.byKey(const Key('camera_settings_button')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Default camera'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('changing aspect ratio recreates the same camera', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));

      expect(fakeCameraPlatform.createdDescriptions, hasLength(1));
      expect(fakeCameraPlatform.createdDescriptions.single.name, '0');

      await tester.tap(find.text('4:3'));
      await tester.pump(const Duration(milliseconds: 300));
      final menuItem = find.widgetWithText(PopupMenuItem<double>, '16:9');
      Navigator.of(tester.element(menuItem)).pop<double>(16 / 9);
      await tester.pump(const Duration(seconds: 1));

      expect(fakeCameraPlatform.createdDescriptions, hasLength(2));
      expect(fakeCameraPlatform.createdDescriptions.last.name, '0');
      expect(
        await PreferencesService.loadAspectRatio(),
        closeTo(16 / 9, 0.001),
      );
    });

    testWidgets(
      'timeburst waits for a pending shutter before starting another',
      (tester) async {
        final pending = Completer<XFile>();
        fakeCameraPlatform.pendingPhoto = pending.future;
        PreferencesService.testData['captureMode'] = 'timeburst';
        await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.byKey(const Key('capture_button')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(fakeCameraPlatform.photoRequests, 1);
        await tester.pump(const Duration(seconds: 3));
        expect(fakeCameraPlatform.photoRequests, 1);
        await tester.tap(find.byKey(const Key('capture_button')));
        await tester.pump();
        expect(find.textContaining('Timeburst: 0'), findsOneWidget);
        pending.completeError(StateError('test shutter cancelled'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(fakeCameraPlatform.photoRequests, 1);
        expect(find.textContaining('Timeburst: 0'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'cannot capture in the old mode while a mode switch is pending',
      (tester) async {
        PreferencesService.testData['captureMode'] = 'video';
        await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
        await tester.pump(const Duration(seconds: 2));
        final stop = Completer<void>();
        final photo = Completer<XFile>();
        pendingMonitoringStop = stop.future;
        fakeCameraPlatform.pendingPhoto = photo.future;
        await tester.tap(find.text('PHOTO'));
        await tester.pump();
        await tester.tap(find.byKey(const Key('capture_button')));
        await tester.pump();
        expect(fakeCameraPlatform.photoRequests, 0);
        stop.complete();
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const Key('capture_button')));
        await tester.pump();
        expect(fakeCameraPlatform.photoRequests, 1);
        photo.completeError(StateError('test shutter cancelled'));
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'releasing a long press stops a recording that is still starting',
      (tester) async {
        mockCameraMaps.add({
          'id': '2',
          'lensFacing': 1,
          'sensorOrientation': 90,
        });
        final start = Completer<void>();
        fakeCameraPlatform.pendingVideoStart = start.future;
        await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
        await tester.pump(const Duration(seconds: 2));
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('capture_button'))),
        );
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        await tester.pump();
        expect(fakeCameraPlatform.videoStartRequests, 1);
        await gesture.up();
        await tester.pump();
        expect(fakeCameraPlatform.videoStopRequests, 0);
        start.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(fakeCameraPlatform.videoStopRequests, 1);
        await tester.pump();
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('camera_lens_2')))
              .onSelected,
          isNotNull,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'changing resolution reconfigures the preview with the selected preset',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
        await tester.pump(const Duration(seconds: 2));

        expect(fakeCameraPlatform.createdDescriptions, hasLength(1));

        await tester.tap(find.text('Maks'));
        await tester.pump(const Duration(milliseconds: 300));
        final menuItem = find.widgetWithText(
          PopupMenuItem<ResolutionPreset>,
          '720p',
        );
        Navigator.of(
          tester.element(menuItem),
        ).pop<ResolutionPreset>(ResolutionPreset.high);
        await tester.pump(const Duration(milliseconds: 300));

        expect(fakeCameraPlatform.createdDescriptions, hasLength(2));
        expect(fakeCameraPlatform.createdPresets.last, ResolutionPreset.high);
        expect(
          await PreferencesService.loadResolution(),
          ResolutionPreset.high,
        );
      },
    );

    testWidgets(
      'viewfinder follows physical orientation and freezes its ratio during recording',
      (tester) async {
        PreferencesService.testData['captureMode'] = CaptureMode.video.name;
        await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
        await tester.pump(const Duration(seconds: 2));
        double frameRatio() => tester
            .widget<AspectRatio>(
              find.byKey(const Key('camera_viewfinder_frame')),
            )
            .aspectRatio;
        expect(frameRatio(), closeTo(3 / 4, 0.001));
        fakeCameraPlatform.orientationEvents.add(
          const DeviceOrientationChangedEvent(DeviceOrientation.landscapeLeft),
        );
        await tester.pump();
        expect(frameRatio(), closeTo(4 / 3, 0.001));
        await tester.tap(find.byKey(const Key('capture_button')));
        await tester.pump(const Duration(seconds: 1));
        expect(fakeCameraPlatform.videoStartRequests, 1);
        fakeCameraPlatform.orientationEvents.add(
          const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp),
        );
        await tester.pump();
        expect(frameRatio(), closeTo(4 / 3, 0.001));
        expect(find.byType(PopupMenuButton<double>), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('photo capture shows shutter feedback without success snackbar', (
      WidgetTester tester,
    ) async {
      final photo = File('${Directory.systemTemp.path}/capture_flash_test.jpg');
      final fixtureBytes = base64Decode(
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==',
      );
      photo.writeAsBytesSync(fixtureBytes);
      fakeCameraPlatform.picturePath = photo.path;

      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byKey(const Key('capture_button')), findsOneWidget);
      expect(
        tester
            .widget<CaptureFlashOverlay>(
              find.byKey(const Key('capture_flash_overlay')),
            )
            .visible,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('capture_button')));
      await tester.pump();

      expect(
        tester
            .widget<CaptureFlashOverlay>(
              find.byKey(const Key('capture_flash_overlay')),
            )
            .visible,
        isTrue,
      );

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();

      expect(
        tester
            .widget<CaptureFlashOverlay>(
              find.byKey(const Key('capture_flash_overlay')),
            )
            .visible,
        isFalse,
      );
      expect(find.text('Fotoğraf kaydedildi'), findsNothing);

      if (photo.existsSync()) photo.deleteSync();
    });

    testWidgets('lens selector shows only classified rear lenses', (
      WidgetTester tester,
    ) async {
      mockCameraMaps = <Map<String, Object>>[
        <String, Object>{
          'id': '0',
          'lensFacing': 1,
          'sensorOrientation': 90,
          'focalLengths': <double>[4.0],
          'sensorWidth': 6.4,
          'sensorHeight': 4.8,
          'minimumFocusDistance': 10.0,
          'maxJpegWidth': 4000,
          'maxJpegHeight': 3000,
          'physicalCameraIds': <String>[],
        },
        <String, Object>{
          'id': '3',
          'lensFacing': 1,
          'sensorOrientation': 90,
          'focalLengths': <double>[2.0],
          'sensorWidth': 3.2,
          'sensorHeight': 2.4,
          'minimumFocusDistance': 33.33,
          'maxJpegWidth': 1600,
          'maxJpegHeight': 1200,
          'physicalCameraIds': <String>[],
        },
        <String, Object>{
          'id': '2',
          'lensFacing': 1,
          'sensorOrientation': 90,
          'focalLengths': <double>[1.6],
          'sensorWidth': 6.4,
          'sensorHeight': 4.8,
          'minimumFocusDistance': 4.0,
          'maxJpegWidth': 3264,
          'maxJpegHeight': 2448,
          'physicalCameraIds': <String>[],
        },
        <String, Object>{
          'id': '1',
          'lensFacing': 0,
          'sensorOrientation': 90,
          'focalLengths': <double>[3.0],
          'sensorWidth': 4.0,
          'sensorHeight': 3.0,
          'minimumFocusDistance': 5.0,
          'maxJpegWidth': 3000,
          'maxJpegHeight': 2000,
          'physicalCameraIds': <String>[],
        },
      ];

      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Wide'), findsOneWidget);
      expect(find.text('Makro'), findsOneWidget);
      expect(find.text('Ultra wide'), findsOneWidget);
      expect(find.text('Front camera'), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('camera_lens_3')));
      await tester.tap(find.byKey(const ValueKey('camera_lens_3')));
      await tester.pump(const Duration(seconds: 1));
      expect(fakeCameraPlatform.createdDescriptions.last.name, '3');

      await tester.ensureVisible(find.byKey(const ValueKey('camera_lens_2')));
      await tester.tap(find.byKey(const ValueKey('camera_lens_2')));
      await tester.pump(const Duration(seconds: 1));
      expect(fakeCameraPlatform.createdDescriptions.last.name, '2');
    });

    test(
      'failed lens switch restores preview and keeps saved selection',
      () async {
        mockCameraMaps = <Map<String, Object>>[
          <String, Object>{'id': '0', 'lensFacing': 1, 'sensorOrientation': 90},
          <String, Object>{'id': '3', 'lensFacing': 1, 'sensorOrientation': 90},
        ];
        final service = CameraService();
        await service.initialize();
        fakeCameraPlatform.failingCameraIds.add('3');
        await expectLater(
          service.switchBackLens(1),
          throwsA(isA<CameraException>()),
        );
        expect(service.currentCameraId, '0');
        expect(service.currentBackCameraIndex, 0);
        expect(service.isInitialized, isTrue);
        expect(await PreferencesService.loadSelectedCameraId(), isNull);
        service.dispose();
      },
    );

    testWidgets('camera error replaces frozen preview with recovery control', (
      WidgetTester tester,
    ) async {
      final service = CameraService();
      await service.initialize();
      var recovered = false;
      await tester.pumpWidget(
        MaterialApp(
          home: CameraPreviewGuard(
            controller: service.controller!,
            onRecover: () => recovered = true,
            child: const Text('Preview'),
          ),
        ),
      );
      service.controller!.value = service.controller!.value.copyWith(
        errorDescription: 'Camera disconnected',
      );
      await tester.pump();
      expect(service.isInitialized, isFalse);
      expect(find.text('Preview'), findsNothing);
      expect(find.text('Camera connection was lost.'), findsOneWidget);
      await tester.tap(find.text('Return to main camera'));
      expect(recovered, isTrue);
      await tester.pumpWidget(const SizedBox());
      service.dispose();
    });

    testWidgets('camera switch button opens the front camera', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));

      await tester.tap(find.byIcon(Icons.cameraswitch_rounded));
      await tester.pump(const Duration(seconds: 1));

      expect(fakeCameraPlatform.createdDescriptions.last.name, '1');
    });

    testWidgets('restores the saved rear lens on startup', (
      WidgetTester tester,
    ) async {
      PreferencesService.testData = <String, dynamic>{'selectedCameraId': '2'};
      mockCameraMaps = <Map<String, Object>>[
        <String, Object>{'id': '0', 'lensFacing': 1, 'sensorOrientation': 90},
        <String, Object>{'id': '2', 'lensFacing': 1, 'sensorOrientation': 90},
      ];

      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));

      expect(fakeCameraPlatform.createdDescriptions.last.name, '2');
    });

    testWidgets('Should display top camera controls', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Check if top AppBar camera controls are visible.
      expect(find.text('Maks'), findsOneWidget);
      expect(find.text('4:3'), findsOneWidget);
      expect(find.byIcon(Icons.flash_auto), findsOneWidget);
      expect(find.byIcon(Icons.cameraswitch_rounded), findsOneWidget);
    });

    testWidgets('Should show FocusIndicatorWidget on preview tap', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Tap on the preview center coordinate
      await tester.tapAt(const Offset(400, 300));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(); // Render frame

      // Should render FocusIndicatorWidget
      expect(find.byType(FocusIndicatorWidget), findsOneWidget);

      // Settle down focus indicator timer
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(FocusIndicatorWidget), findsNothing);
    });

    testWidgets(
      'Should show BrightnessSliderWidget on long press and vertical drag',
      (WidgetTester tester) async {
        await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
        await tester.pump(const Duration(seconds: 2));
        await tester.pump();

        // Long press and drag up
        final gesture = await tester.startGesture(const Offset(400, 300));
        await tester.pump(
          const Duration(milliseconds: 600),
        ); // Trigger long press

        // Now drag up
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(); // Render frame

        // Should show BrightnessSliderWidget
        expect(find.byType(BrightnessSliderWidget), findsOneWidget);

        await gesture.up();
        await tester.pump();

        // Settle down exposure slider fade timer (2 seconds)
        await tester.pump(const Duration(seconds: 3));
        expect(find.byType(BrightnessSliderWidget), findsNothing);
      },
    );

    testWidgets('Should render readable audio level panel in Video mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      // Tap Video mode to switch capture mode.
      final videoModeBtn = find.text('VIDEO');
      expect(videoModeBtn, findsOneWidget);

      await tester.tap(videoModeBtn);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.byKey(const Key('audio_level_panel')), findsOneWidget);
      expect(find.byKey(const Key('audio_peak_meter')), findsOneWidget);
      expect(find.textContaining('LEVEL '), findsOneWidget);
    });

    testWidgets('restores and persists the audio waveform visibility', (
      WidgetTester tester,
    ) async {
      PreferencesService.testData = <String, dynamic>{
        'captureMode': CaptureMode.video.name,
        'audioWaveformVisible': false,
      };

      await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(find.byKey(const Key('audio_level_panel')), findsNothing);
      expect(
        find.byKey(const Key('audio_waveform_show_button')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('audio_waveform_show_button')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 20; attempt++) {
          if (await PreferencesService.loadAudioWaveformVisible()) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });

      expect(find.byKey(const Key('audio_level_panel')), findsOneWidget);
      expect(await PreferencesService.loadAudioWaveformVisible(), isTrue);
    });
  });
}
