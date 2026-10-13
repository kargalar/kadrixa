import 'package:camerapro/services/media_muxer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android metadata preserves portrait output dimensions', () {
    expect(
      MediaMuxerService.displayedVideoSize({
        'width': 1280,
        'height': 720,
        'rotation': 270,
      }),
      (width: 720, height: 1280),
    );
  });
  test('portrait dimensions respect legacy rotation tags', () {
    expect(
      MediaMuxerService.displayedVideoSize({
        'width': 1280,
        'height': 720,
        'tags': {'rotate': '90'},
      }),
      (width: 720, height: 1280),
    );
  });

  test('display matrix rotation takes precedence over legacy tags', () {
    expect(
      MediaMuxerService.displayedVideoSize({
        'width': 1280,
        'height': 720,
        'tags': {'rotate': '0'},
        'side_data_list': [
          {'rotation': -90},
        ],
      }),
      (width: 720, height: 1280),
    );
  });

  test('invalid dimensions cannot start segment normalization', () {
    expect(
      () => MediaMuxerService.displayedVideoSize({'width': 0, 'height': 720}),
      throwsA(isA<MediaProcessingException>()),
    );
  });
}
