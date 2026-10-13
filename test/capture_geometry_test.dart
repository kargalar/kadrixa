import 'package:camerapro/models/capture_geometry.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camera/camera.dart';

void main() {
  test(
    'resolution caps the short edge without changing framing or upscaling',
    () {
      expect(
        CaptureGeometry.videoSize(768, 1024, 3 / 4, ResolutionPreset.high),
        (width: 720, height: 960),
      );
      expect(
        CaptureGeometry.videoSize(1920, 1080, 4 / 3, ResolutionPreset.high),
        (width: 960, height: 720),
      );
      expect(
        CaptureGeometry.videoSize(640, 480, 4 / 3, ResolutionPreset.high),
        (width: 640, height: 480),
      );
      expect(
        CaptureGeometry.videoSize(
          2160,
          3840,
          9 / 16,
          ResolutionPreset.veryHigh,
        ),
        (width: 1080, height: 1920),
      );
    },
  );
  test('portrait and landscape retain the selected framing', () {
    for (final ratio in [4 / 3, 16 / 9, 1.0]) {
      for (final orientation in DeviceOrientation.values) {
        final oriented = CaptureGeometry.orientedAspectRatio(
          ratio,
          orientation,
        );
        final landscape = CaptureGeometry.isLandscape(orientation);
        final crop = CaptureGeometry.cropSize(
          landscape ? 1920 : 1080,
          landscape ? 1080 : 1920,
          oriented,
        );
        expect(crop.width / crop.height, closeTo(oriented, 0.003));
        expect(crop.width.isEven && crop.height.isEven, isTrue);
      }
    }
  });

  test('wide recording is center cropped to the portrait viewfinder', () {
    expect(CaptureGeometry.cropSize(720, 1280, 3 / 4), (
      width: 720,
      height: 960,
    ));
    expect(CaptureGeometry.cropSize(1280, 720, 4 / 3), (
      width: 960,
      height: 720,
    ));
    expect(CaptureGeometry.cropSize(1280, 720, 1), (width: 720, height: 720));
  });
}
