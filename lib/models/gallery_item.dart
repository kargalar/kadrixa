enum GalleryItemStatus { processing, success, failed }

class GalleryItem {
  GalleryItem({
    required this.id,
    required this.path,
    required this.isPhoto,
    this.thumbnailPath,
    DateTime? timestamp,
    this.status = GalleryItemStatus.success,
    this.errorMessage,
  }) : timestamp = timestamp ?? DateTime.now();

  final String id;
  final String path;
  final String? thumbnailPath;
  final bool isPhoto;
  final DateTime timestamp;
  final GalleryItemStatus status;
  final String? errorMessage;

  GalleryItem copyWith({
    String? path,
    String? thumbnailPath,
    bool clearThumbnail = false,
    GalleryItemStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return GalleryItem(
      id: id,
      path: path ?? this.path,
      thumbnailPath: clearThumbnail
          ? null
          : (thumbnailPath ?? this.thumbnailPath),
      isPhoto: isPhoto,
      timestamp: timestamp,
      status: status ?? this.status,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'path': path,
    'thumbnailPath': thumbnailPath,
    'isPhoto': isPhoto,
    'timestamp': timestamp.toIso8601String(),
    'status': status.name,
    'errorMessage': errorMessage,
  };

  factory GalleryItem.fromJson(Map<String, dynamic> json) {
    return GalleryItem(
      id: json['id'] as String,
      path: json['path'] as String,
      thumbnailPath: json['thumbnailPath'] as String?,
      isPhoto: json['isPhoto'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: GalleryItemStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => GalleryItemStatus.success,
      ),
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
