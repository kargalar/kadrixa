import 'package:camerapro/models/capture_mode.dart';
import 'package:camerapro/services/camera_intent_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(
    () => messenger.setMockMethodCallHandler(CameraIntentService.channel, null),
  );

  test('normal launcher does not enter a capture-for-result session', () async {
    messenger.setMockMethodCallHandler(
      CameraIntentService.channel,
      (_) async => null,
    );
    expect(await CameraIntentService.loadRequest(), isNull);
  });

  test('video request reads caller quality and duration constraints', () {
    final request = CameraLaunchRequest.fromMap({
      'mode': 'video',
      'returnCapture': true,
      'durationLimitSeconds': 3,
      'lowVideoQuality': true,
    });
    expect(request.mode, CaptureMode.video);
    expect(request.returnCapture, isTrue);
    expect(request.durationLimitSeconds, 3);
    expect(request.lowVideoQuality, isTrue);
  });

  test('negative duration cannot trigger an immediate stop', () {
    expect(
      CameraLaunchRequest.fromMap({
        'durationLimitSeconds': -5,
      }).durationLimitSeconds,
      0,
    );
  });

  test('completed capture passes the source path to Android', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(CameraIntentService.channel, (
      call,
    ) async {
      received = call;
      return null;
    });
    await CameraIntentService.complete('/private/capture.jpg');
    expect(received?.method, 'completeCapture');
    expect(received?.arguments, {'path': '/private/capture.jpg'});
  });

  test('default camera action requests the Android camera selector', () async {
    String? method;
    messenger.setMockMethodCallHandler(CameraIntentService.channel, (
      call,
    ) async {
      method = call.method;
      return null;
    });
    await CameraIntentService.openCameraSelector();
    expect(method, 'openCameraSelector');
  });
}
