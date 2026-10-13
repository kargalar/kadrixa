import 'package:camerapro/utils/media_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaFileName', () {
    final timestamp = DateTime(2026, 7, 27, 14, 30, 52, 123);

    test('creates a sortable photo name', () {
      expect(
        MediaFileName.create(MediaFileType.photo, timestamp: timestamp),
        'IMG_20260727_143052_123.jpg',
      );
    });

    test('creates a sortable video name', () {
      expect(
        MediaFileName.create(MediaFileType.video, timestamp: timestamp),
        'VID_20260727_143052_123.mp4',
      );
    });

    test('creates a sortable timeburst name', () {
      expect(
        MediaFileName.create(MediaFileType.timelapse, timestamp: timestamp),
        'TIMELAPSE_20260727_143052_123.mp4',
      );
    });
  });
}
