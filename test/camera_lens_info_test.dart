import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:camerapro/models/camera_lens_info.dart';

CameraLensInfo lens({
  required String id,
  double? equivalentMm,
  int? pixels,
  double? minimumFocusDistance,
}) {
  return CameraLensInfo(
    description: CameraDescription(
      name: id,
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
    equivalentFocalLength: equivalentMm,
    maxJpegPixels: pixels,
    minimumFocusDistance: minimumFocusDistance,
  );
}

void main() {
  group('CameraLensInfo', () {
    test('parses platform metadata and calculates equivalent focal length', () {
      final info = CameraLensInfo.fromPlatformMap(<Object?, Object?>{
        'id': '0',
        'lensFacing': 1,
        'sensorOrientation': 90,
        'focalLengths': <double>[4.0],
        'sensorWidth': 6.4,
        'sensorHeight': 4.8,
        'minimumFocusDistance': 10.0,
        'maxJpegWidth': 4000,
        'maxJpegHeight': 3000,
        'physicalCameraIds': <String>['2', '3'],
      });

      expect(info.description.name, '0');
      expect(info.description.lensDirection, CameraLensDirection.back);
      expect(info.equivalentFocalLength, closeTo(21.63, 0.1));
      expect(info.maxJpegPixels, 12000000);
      expect(info.physicalCameraIds, <String>['2', '3']);
    });

    test('classifies focal lengths as ultra wide, wide, and telephoto', () {
      final classified = CameraLensClassifier.classify(<CameraLensInfo>[
        lens(id: '2', equivalentMm: 14, pixels: 8000000),
        lens(id: '0', equivalentMm: 24, pixels: 12000000),
        lens(id: '4', equivalentMm: 70, pixels: 10000000),
      ]);

      expect(classified[0].kind, CameraLensKind.ultraWide);
      expect(classified[1].kind, CameraLensKind.wide);
      expect(classified[2].kind, CameraLensKind.telephoto);
    });

    test('classifies a five megapixel lens with close macro focus', () {
      final classified = CameraLensClassifier.classify(<CameraLensInfo>[
        lens(id: '0', equivalentMm: 24, pixels: 12000000),
        lens(
          id: '3',
          equivalentMm: 27,
          pixels: 2592 * 1944,
          minimumFocusDistance: 33.33,
        ),
      ]);

      expect(classified[1].kind, CameraLensKind.macro);
      expect(classified[1].displayLabel(1), 'Makro');
    });

    test('does not mistake fixed focus for macro capability', () {
      final classified = CameraLensClassifier.classify(<CameraLensInfo>[
        lens(id: '0', equivalentMm: 24, pixels: 12000000),
        lens(
          id: 'aux',
          equivalentMm: 27,
          pixels: 2000000,
          minimumFocusDistance: 0,
        ),
      ]);
      expect(classified[1].kind, CameraLensKind.unknown);
    });

    test('uses a neutral label when metadata is ambiguous', () {
      final classified = CameraLensClassifier.classify(<CameraLensInfo>[
        lens(id: 'rear-aux'),
      ]);

      expect(classified.single.kind, CameraLensKind.unknown);
      expect(classified.single.displayLabel(0), 'Camera 1');
    });
  });
}
