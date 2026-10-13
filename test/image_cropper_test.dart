import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camerapro/utils/image_cropper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  const red = [230, 20, 20];
  const green = [20, 210, 20];
  const blue = [20, 20, 230];
  const yellow = [230, 210, 20];
  const mirroredCorners = {
    1: [green, red, yellow, blue],
    2: [green, red, yellow, blue],
    3: [blue, yellow, red, green],
    4: [blue, yellow, red, green],
    5: [red, blue, green, yellow],
    6: [red, blue, green, yellow],
    7: [yellow, green, blue, red],
    8: [yellow, green, blue, red],
  };

  for (final orientation in mirroredCorners.keys) {
    test(
      'matches mirrored preview for EXIF orientation $orientation',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'photo_mirror_',
        );
        final file = File('${directory.path}/capture.jpg');
        final source = img.Image(width: 80, height: 60);
        for (final pixel in source) {
          final color = pixel.y < 30
              ? (pixel.x < 40 ? red : green)
              : (pixel.x < 40 ? blue : yellow);
          pixel.setRgb(color[0], color[1], color[2]);
        }
        source.exif.imageIfd.orientation = orientation;
        await file.writeAsBytes(img.encodeJpg(source, quality: 100));
        try {
          await cropImageToAspectRatio(
            XFile(file.path),
            4 / 3,
            mirrorHorizontally: true,
          );
          final result = img.decodeJpg(await file.readAsBytes())!;
          final expectedSize = orientation >= 5 ? [60, 80] : [80, 60];
          expect([result.width, result.height], expectedSize);
          final corners = [
            result.getPixel(8, 8),
            result.getPixel(result.width - 9, 8),
            result.getPixel(8, result.height - 9),
            result.getPixel(result.width - 9, result.height - 9),
          ];
          for (var index = 0; index < corners.length; index++) {
            final pixel = corners[index];
            final expected = mirroredCorners[orientation]![index];
            expect(pixel.r, closeTo(expected[0], 15));
            expect(pixel.g, closeTo(expected[1], 15));
            expect(pixel.b, closeTo(expected[2], 15));
          }
          final processedBytes = await file.readAsBytes();
          // Recovering a durable photo job must keep the same orientation.
          await cropImageToAspectRatio(
            XFile(file.path),
            4 / 3,
            mirrorHorizontally: true,
          );
          expect(await file.readAsBytes(), orderedEquals(processedBytes));
          await cropImageToAspectRatio(
            XFile(file.path),
            1,
            mirrorHorizontally: true,
          );
          final square = img.decodeJpg(await file.readAsBytes())!;
          expect(square.width, square.height);
          final squareTopLeft = square.getPixel(8, 8);
          expect(
            squareTopLeft.r,
            closeTo(mirroredCorners[orientation]![0][0], 15),
          );
          expect(
            squareTopLeft.g,
            closeTo(mirroredCorners[orientation]![0][1], 15),
          );
          expect(
            squareTopLeft.b,
            closeTo(mirroredCorners[orientation]![0][2], 15),
          );
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );
  }

  test('reads JPEG dimensions without decoding pixels', () {
    final bytes = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 40, height: 30)),
    );

    expect(
      readJpegDimensions(bytes),
      const JpegDimensions(width: 40, height: 30),
    );
    expect(readJpegDimensions(Uint8List.fromList(<int>[0, 1, 2])), isNull);
  });

  test(
    'leaves JPEG bytes untouched when aspect ratio already matches',
    () async {
      final file = File('${Directory.systemTemp.path}/matching_ratio.jpg');
      final original = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 40, height: 30)),
      );
      file.writeAsBytesSync(original);

      final result = await cropImageToAspectRatio(XFile(file.path), 4 / 3);

      expect(result?.path, file.path);
      expect(file.readAsBytesSync(), orderedEquals(original));
      file.deleteSync();
    },
  );

  test('crops a mismatched JPEG to the requested ratio', () async {
    final file = File('${Directory.systemTemp.path}/square_crop.jpg');
    file.writeAsBytesSync(img.encodeJpg(img.Image(width: 40, height: 30)));

    final result = await cropImageToAspectRatio(XFile(file.path), 1);
    final decoded = img.decodeJpg(File(result!.path).readAsBytesSync());

    expect(decoded, isNotNull);
    expect(decoded!.width, decoded.height);
    file.deleteSync();
  });

  test(
    'keeps portrait orientation when cropping an EXIF-rotated JPEG',
    () async {
      final file = File('${Directory.systemTemp.path}/portrait_crop.jpg');
      final image = img.Image(width: 80, height: 60);
      image.exif.imageIfd.orientation = 6;
      file.writeAsBytesSync(img.encodeJpg(image));
      try {
        await cropImageToAspectRatio(XFile(file.path), 16 / 9);
        final result = img.decodeJpg(file.readAsBytesSync())!;
        expect(result.width, 45);
        expect(result.height, 80);
      } finally {
        await file.delete();
      }
    },
  );

  test('does not report an unreadable photo as a successful crop', () async {
    final file = File('${Directory.systemTemp.path}/invalid_capture.jpg');
    await file.writeAsBytes([0, 1, 2]);
    try {
      await expectLater(
        cropImageToAspectRatio(XFile(file.path), 1),
        throwsA(isA<img.ImageException>()),
      );
    } finally {
      await file.delete();
    }
  });
}
