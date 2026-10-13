import 'dart:async';

import 'package:camerapro/screens/dual_camera_screen.dart';
import 'package:camerapro/services/dual_camera_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';

class FakeDualCameraService extends DualCameraService {
  final failures = StreamController<String>.broadcast();
  final orientationChanges = StreamController<DeviceOrientation>.broadcast();
  final configuredOrientations = <DeviceOrientation>[];
  final swaps = <bool>[];
  bool unsupported = false;
  int starts = 0;
  int stops = 0;
  int releases = 0;
  String? microphone;
  Future<void>? pendingStart;

  @override
  Stream<String> get errors => failures.stream;
  @override
  Stream<DeviceOrientation> get orientations => orientationChanges.stream;
  @override
  Future<DualCameraPreview> initialize({
    double aspectRatio = 16 / 9,
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
    DeviceOrientation orientation = DeviceOrientation.portraitUp,
  }) async {
    if (unsupported) {
      throw PlatformException(
        code: 'dualCameraUnavailable',
        message:
            'Dual-camera mode is currently available only on Android devices.',
      );
    }
    return const DualCameraPreview(textureId: 42, width: 720, height: 1280);
  }

  @override
  Future<DualCameraPreview> configure({
    required double aspectRatio,
    required ResolutionPreset resolutionPreset,
    required DeviceOrientation orientation,
  }) async {
    configuredOrientations.add(orientation);
    final frame = DualCameraService.frameConfiguration(
      aspectRatio: aspectRatio,
      resolutionPreset: resolutionPreset,
      orientation: orientation,
    );
    return DualCameraPreview(
      textureId: 42,
      width: frame['width']!.toDouble(),
      height: frame['height']!.toDouble(),
    );
  }

  @override
  Future<void> swap({required bool frontIsMain}) async =>
      swaps.add(frontIsMain);
  @override
  Future<void> startRecording({String? microphoneId}) async {
    starts++;
    microphone = microphoneId;
    await pendingStart;
  }

  @override
  Future<String?> stopRecording() async {
    stops++;
    return null;
  }

  @override
  Future<void> dispose() async {
    releases++;
  }
}

void main() {
  late FakeDualCameraService service;
  const wakelockChannel =
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';

  setUp(() {
    service = FakeDualCameraService();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          wakelockChannel,
          (_) async => const StandardMessageCodec().encodeMessage([null]),
        );
  });
  tearDown(() async {
    await service.failures.close();
    await service.orientationChanges.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(wakelockChannel, null);
  });

  testWidgets(
    'dual frame rotates before recording and retains the start direction',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DualCameraScreen(service: service, aspectRatio: 4 / 3),
        ),
      );
      await tester.pump();
      service.orientationChanges.add(DeviceOrientation.landscapeLeft);
      await tester.pump();
      expect(find.text('960 × 720 · Front + rear'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dual_camera_capture')));
      await tester.pump();
      final configurationCount = service.configuredOrientations.length;
      service.orientationChanges.add(DeviceOrientation.portraitUp);
      await tester.pump();
      expect(service.configuredOrientations, hasLength(configurationCount));
      expect(find.text('960 × 720 · Front + rear'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dual_camera_capture')));
      await tester.pump();
      expect(find.text('720 × 960 · Front + rear'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('both images can swap before and during the same recording', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DualCameraScreen(service: service, microphoneId: 'mic-2'),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('dual_camera_preview')), findsOneWidget);
    expect(find.text(DualCameraStrings.rearMain), findsOneWidget);
    await tester.tap(find.byKey(const Key('dual_camera_swap')));
    await tester.pump();
    expect(find.text(DualCameraStrings.frontMain), findsOneWidget);
    await tester.tap(find.byKey(const Key('dual_camera_capture')));
    await tester.pump();
    expect(service.starts, 1);
    expect(service.microphone, 'mic-2');
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:02'), findsOneWidget);
    await tester.tap(find.byKey(const Key('dual_camera_swap')));
    await tester.pump();
    expect(service.swaps, [false, true, false]);
    expect(service.starts, 1);
    expect(service.stops, 0);
    await tester.tap(find.byKey(const Key('dual_camera_capture')));
    await tester.pump();
    expect(service.stops, 1);
    expect(find.text(DualCameraStrings.rearMain), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unsupported devices explain why capture is unavailable', (
    tester,
  ) async {
    service.unsupported = true;
    await tester.pumpWidget(
      MaterialApp(home: DualCameraScreen(service: service)),
    );
    await tester.pump();
    expect(
      find.text(
        'Dual-camera mode is currently available only on Android devices.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('dual_camera_preview')), findsNothing);
    final capture = tester.widget<IconButton>(
      find.byKey(const Key('dual_camera_capture')),
    );
    expect(capture.onPressed, isNull);
    expect(service.starts, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('camera failure stops the timer and disables capture', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: DualCameraScreen(service: service)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('dual_camera_capture')));
    await tester.pump();
    service.failures.add('Camera connection was lost.');
    await tester.pump();
    expect(find.text('Camera connection was lost.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('00:03'), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('dual_camera_capture')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('backgrounding waits for a starting recording and finalizes it', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final start = Completer<void>();
    service.pendingStart = start.future;
    await tester.pumpWidget(
      MaterialApp(home: DualCameraScreen(service: service)),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('dual_camera_capture')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    start.complete();
    await tester.pump();
    await tester.pump();
    expect(service.stops, 1);
    expect(service.releases, 1);
    expect(find.byKey(const Key('dual_camera_preview')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
}
