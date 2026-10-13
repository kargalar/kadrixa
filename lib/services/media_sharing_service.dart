import 'dart:io';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import '../models/gallery_item.dart';

class MediaSharingService {
  MediaSharingService({SharePlus? client})
    : _client = client ?? SharePlus.instance;

  final SharePlus _client;

  Future<void> share(GalleryItem item, {required Rect origin}) async {
    final file = File(item.path);
    if (!await file.exists() || await file.length() == 0) {
      throw FileSystemException('Media file is missing or empty', item.path);
    }
    await _client.share(
      ShareParams(
        files: [
          XFile(item.path, mimeType: item.isPhoto ? 'image/jpeg' : 'video/mp4'),
        ],
        sharePositionOrigin: origin,
      ),
    );
  }
}
