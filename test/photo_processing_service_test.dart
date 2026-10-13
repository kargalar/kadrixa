import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camerapro/services/photo_processing_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/native_photo_processor');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'uses native Android processing and returns the processed path',
    () async {
      MethodCall? receivedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            receivedCall = call;
            return <String, Object?>{
              'success': true,
              'path': '/tmp/processed.jpg',
              'galleryUri': 'content://images/42',
              'didCrop': true,
            };
          });

      final service = PhotoProcessingService(
        channel: channel,
        useNativeAndroidPipeline: true,
        fallbackCrop: (_, _, {mirrorHorizontally = false}) =>
            fail('Dart crop fallback should not run'),
        fallbackSave: (_) => fail('Gallery fallback should not run'),
      );

      final result = await service.process(
        XFile('/tmp/raw.jpg'),
        targetAspectRatio: 1,
        saveToGallery: true,
        mirrorHorizontally: true,
      );

      expect(result.success, isTrue);
      expect(result.path, '/tmp/processed.jpg');
      expect(result.galleryUri, 'content://images/42');
      expect(result.didCrop, isTrue);
      expect(receivedCall?.method, 'processAndSavePhoto');
      expect(receivedCall?.arguments, <String, Object?>{
        'sourcePath': '/tmp/raw.jpg',
        'targetAspectRatio': 1.0,
        'jpegQuality': 95,
        'saveToGallery': true,
        'mirrorHorizontally': true,
      });
    },
  );

  test(
    'falls back to the Dart pipeline when native processing is unavailable',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw MissingPluginException();
          });

      var savedPath = '';
      var receivedMirror = false;
      final service = PhotoProcessingService(
        channel: channel,
        useNativeAndroidPipeline: true,
        fallbackCrop: (file, _, {mirrorHorizontally = false}) async {
          receivedMirror = mirrorHorizontally;
          return XFile('/tmp/cropped.jpg');
        },
        fallbackSave: (path) async {
          savedPath = path;
          return true;
        },
      );

      final result = await service.process(
        XFile('/tmp/raw.jpg'),
        targetAspectRatio: 4 / 3,
        saveToGallery: true,
        mirrorHorizontally: true,
      );

      expect(result.success, isTrue);
      expect(result.path, '/tmp/cropped.jpg');
      expect(result.galleryUri, isNull);
      expect(savedPath, '/tmp/cropped.jpg');
      expect(receivedMirror, isTrue);
    },
  );

  test(
    'propagates native errors without saving the photo a second time',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'GALLERY_WRITE_FAILED');
          });
      final service = PhotoProcessingService(
        channel: channel,
        useNativeAndroidPipeline: true,
        fallbackCrop: (_, _, {mirrorHorizontally = false}) =>
            fail('Failed native work must not run twice'),
        fallbackSave: (_) => fail('Gallery insertion must not run twice'),
      );
      await expectLater(
        service.process(
          XFile('/tmp/raw.jpg'),
          targetAspectRatio: 1,
          saveToGallery: true,
        ),
        throwsA(isA<PlatformException>()),
      );
    },
  );
}
