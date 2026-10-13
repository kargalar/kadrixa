enum MediaFileType { photo, video, timelapse }

abstract final class MediaFileName {
  static String create(MediaFileType type, {DateTime? timestamp}) {
    final value = timestamp ?? DateTime.now();
    final date = '${_pad(value.year, 4)}${_pad(value.month)}${_pad(value.day)}';
    final time =
        '${_pad(value.hour)}${_pad(value.minute)}${_pad(value.second)}';
    final suffix = '${date}_${time}_${_pad(value.millisecond, 3)}';

    return switch (type) {
      MediaFileType.photo => 'IMG_$suffix.jpg',
      MediaFileType.video => 'VID_$suffix.mp4',
      MediaFileType.timelapse => 'TIMELAPSE_$suffix.mp4',
    };
  }

  static String _pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');
}
