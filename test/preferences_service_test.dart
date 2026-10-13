import 'dart:io';
import 'dart:isolate';
import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:camerapro/services/preferences_service.dart';
import 'package:camerapro/screens/camera_screen.dart';
import 'package:camerapro/screens/gallery_screen.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
    PreferencesService.documentsDirectoryPathOverrideForTesting = null;
  });

  tearDown(() async {
    try {
      final dir = Directory.systemTemp.path;
      final prefsFile = File('$dir/settings_prefs.json');
      if (await prefsFile.exists()) {
        await prefsFile.delete();
      }
      final galleryFile = File('$dir/gallery_metadata.json');
      if (await galleryFile.exists()) {
        await galleryFile.delete();
      }
    } catch (_) {}
  });

  group('PreferencesService Tests', () {
    test('Should save and load CaptureMode', () async {
      var mode = await PreferencesService.loadCaptureMode();
      expect(mode, CaptureMode.photo);

      await PreferencesService.saveCaptureMode(CaptureMode.video);
      mode = await PreferencesService.loadCaptureMode();
      expect(mode, CaptureMode.video);

      await PreferencesService.saveCaptureMode(CaptureMode.timeburst);
      mode = await PreferencesService.loadCaptureMode();
      expect(mode, CaptureMode.timeburst);
    });

    test('Should save and load FlashMode', () async {
      var mode = await PreferencesService.loadFlashMode();
      expect(mode, FlashMode.auto);

      await PreferencesService.saveFlashMode(FlashMode.always);
      mode = await PreferencesService.loadFlashMode();
      expect(mode, FlashMode.always);
    });

    test('Should save and load ResolutionPreset', () async {
      var preset = await PreferencesService.loadResolution();
      expect(preset, ResolutionPreset.max);

      await PreferencesService.saveResolution(ResolutionPreset.veryHigh);
      preset = await PreferencesService.loadResolution();
      expect(preset, ResolutionPreset.veryHigh);
    });

    test('Should save and load Aspect Ratio', () async {
      var ratio = await PreferencesService.loadAspectRatio();
      expect(ratio, closeTo(4 / 3, 0.01));

      await PreferencesService.saveAspectRatio(16 / 9);
      ratio = await PreferencesService.loadAspectRatio();
      expect(ratio, closeTo(16 / 9, 0.01));
    });

    test('Should save and load Microphone Selection', () async {
      var mic = await PreferencesService.loadSelectedMicrophone();
      expect(mic['id'], isNull);
      expect(mic['label'], isNull);

      await PreferencesService.saveSelectedMicrophone('mic_id_123', 'Bose Mic');
      mic = await PreferencesService.loadSelectedMicrophone();
      expect(mic['id'], 'mic_id_123');
      expect(mic['label'], 'Bose Mic');
    });

    test('Should save and load audio waveform visibility', () async {
      expect(await PreferencesService.loadAudioWaveformVisible(), isTrue);

      await PreferencesService.saveAudioWaveformVisible(false);

      expect(await PreferencesService.loadAudioWaveformVisible(), isFalse);
    });

    test('Should save and load selected rear camera', () async {
      expect(await PreferencesService.loadSelectedCameraId(), isNull);

      await PreferencesService.saveSelectedCameraId('rear-macro');

      expect(await PreferencesService.loadSelectedCameraId(), 'rear-macro');
    });

    test(
      'Should serialize concurrent setting updates without losing values',
      () async {
        await Future.wait([
          PreferencesService.saveCaptureMode(CaptureMode.video),
          PreferencesService.saveFlashMode(FlashMode.always),
          PreferencesService.saveResolution(ResolutionPreset.veryHigh),
          PreferencesService.saveAspectRatio(16 / 9),
          PreferencesService.saveSelectedMicrophone('mic-2', 'USB Mic'),
          PreferencesService.saveAudioWaveformVisible(false),
          PreferencesService.saveSelectedCameraId('rear-macro'),
        ]);

        expect(await PreferencesService.loadCaptureMode(), CaptureMode.video);
        expect(await PreferencesService.loadFlashMode(), FlashMode.always);
        expect(
          await PreferencesService.loadResolution(),
          ResolutionPreset.veryHigh,
        );
        expect(
          await PreferencesService.loadAspectRatio(),
          closeTo(16 / 9, 0.01),
        );
        expect(
          (await PreferencesService.loadSelectedMicrophone())['id'],
          'mic-2',
        );
        expect(await PreferencesService.loadAudioWaveformVisible(), isFalse);
        expect(await PreferencesService.loadSelectedCameraId(), 'rear-macro');
      },
    );

    test('Should save and load Gallery Items', () async {
      final tempFile = File('${Directory.systemTemp.path}/mock_photo.jpg');
      await tempFile.writeAsBytes([0, 1, 2]);

      final items = [
        GalleryItem(
          id: '1',
          path: tempFile.path,
          isPhoto: true,
          timestamp: DateTime(2026, 1, 1),
          status: GalleryItemStatus.success,
        ),
        GalleryItem(
          id: '2',
          path: '',
          isPhoto: false,
          timestamp: DateTime(2026, 1, 2),
          status: GalleryItemStatus.failed,
          errorMessage: 'FFmpeg kodu: 1',
        ),
      ];

      await PreferencesService.saveGalleryItems(items);

      final loaded = await PreferencesService.loadGalleryItems();
      expect(loaded.length, 2);
      expect(loaded.first.id, '1');
      expect(loaded.first.path, tempFile.path);
      expect(loaded.first.isPhoto, true);
      expect(loaded.first.status, GalleryItemStatus.success);
      expect(loaded.last.status, GalleryItemStatus.failed);
      expect(loaded.last.errorMessage, 'FFmpeg kodu: 1');

      await tempFile.delete();
    });

    test('serializes gallery updates across Dart isolates', () async {
      final directory = await Directory.systemTemp.createTemp(
        'camerapro-gallery-metadata-',
      );
      addTearDown(() async {
        PreferencesService.documentsDirectoryPathOverrideForTesting = null;
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      PreferencesService.documentsDirectoryPathOverrideForTesting =
          directory.path;

      await Future.wait(
        List<Future<void>>.generate(
          12,
          (index) => Isolate.run(() async {
            PreferencesService.documentsDirectoryPathOverrideForTesting =
                directory.path;
            await PreferencesService.upsertGalleryItem(
              GalleryItem(
                id: 'video-$index',
                path: '',
                isPhoto: false,
                timestamp: DateTime(2026, 1, index + 1),
                status: GalleryItemStatus.failed,
              ),
            );
          }),
        ),
      );

      final loaded = await PreferencesService.loadGalleryItems();
      expect(loaded, hasLength(12));
      expect(loaded.map((item) => item.id).toSet(), {
        for (var index = 0; index < 12; index++) 'video-$index',
      });
    });
  });
}
