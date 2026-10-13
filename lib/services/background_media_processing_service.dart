import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:workmanager/workmanager.dart';

import '../constants/app_brand.dart';
import '../models/gallery_item.dart';
import '../models/media_location.dart';
import '../utils/media_file_name.dart';
import 'media_job_lock.dart';
import 'media_muxer_service.dart';
import 'photo_processing_service.dart';
import 'preferences_service.dart';
import 'storage_service.dart';

const String _backgroundMediaTask = 'backgroundMediaProcessing';
const String _iosProcessingTaskId =
    '${AppBrand.applicationId}.media_processing';

@pragma('vm:entry-point')
void mediaProcessingCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      if (taskName != _backgroundMediaTask &&
          taskName != _iosProcessingTaskId) {
        return true;
      }

      final itemId = inputData?['itemId'] as String?;
      if (itemId != null) {
        await BackgroundMediaProcessingService.runJob(itemId);
      } else {
        await BackgroundMediaProcessingService.runAllPendingJobs();
      }
      return true;
    } catch (error, stackTrace) {
      // Keep the durable job JSON intact so WorkManager can retry it.
      debugPrint('Background media callback failed: $error\n$stackTrace');
      return false;
    }
  });
}

enum MediaProcessingJobType { photo, video, timeburst }

class EnqueuedMedia {
  const EnqueuedMedia({required this.item});

  final GalleryItem item;
}

class BackgroundMediaProcessingService {
  static bool _workmanagerInitialized = false;
  static Future<void>? _recoveryInProgress;

  static Future<void> initialize() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    await Workmanager().initialize(mediaProcessingCallbackDispatcher);
    _workmanagerInitialized = true;
    await reschedulePendingJobs();
  }

  static Future<EnqueuedMedia> enqueuePhoto({
    required String id,
    required String sourcePath,
    required double targetAspectRatio,
    bool mirrorHorizontally = false,
    MediaLocation? location,
  }) async {
    final mediaDirectory = await _mediaDirectory;
    final persistentPath = path.join(
      mediaDirectory.path,
      MediaFileName.create(MediaFileType.photo),
    );
    await _moveFile(sourcePath, persistentPath);

    final item = GalleryItem(
      id: id,
      path: persistentPath,
      isPhoto: true,
      status: GalleryItemStatus.processing,
    );
    final job = _MediaProcessingJob(
      itemId: id,
      type: MediaProcessingJobType.photo,
      sourcePaths: <String>[persistentPath],
      targetAspectRatio: targetAspectRatio,
      mirrorHorizontally: mirrorHorizontally,
      location: location,
    );
    await _persist(item, job);
    await _schedule(job);
    return EnqueuedMedia(item: item);
  }

  static Future<EnqueuedMedia> enqueueVideo({
    required String id,
    required List<String> videoPaths,
    String? audioPath,
    required ResolutionPreset resolutionPreset,
    double? targetAspectRatio,
    MediaLocation? location,
  }) async {
    final persistentVideos = await _moveInputs(id, videoPaths, prefix: 'video');
    final persistentAudio = audioPath == null
        ? null
        : (await _moveInputs(id, <String>[audioPath], prefix: 'audio')).single;
    final item = GalleryItem(
      id: id,
      path: '',
      isPhoto: false,
      status: GalleryItemStatus.processing,
    );
    final outputPath = await _outputPathForJob(
      id,
      MediaProcessingJobType.video,
    );
    final job = _MediaProcessingJob(
      itemId: id,
      type: MediaProcessingJobType.video,
      sourcePaths: persistentVideos,
      audioPath: persistentAudio,
      targetAspectRatio: targetAspectRatio,
      outputPath: outputPath,
      resolutionPreset: resolutionPreset,
      location: location,
    );
    await _persist(item, job);
    await _schedule(job);
    return EnqueuedMedia(item: item);
  }

  static Future<EnqueuedMedia> enqueueTimeburst({
    required String id,
    required List<String> imagePaths,
    int frameRate = 30,
    ResolutionPreset resolutionPreset = ResolutionPreset.max,
    MediaLocation? location,
  }) async {
    final persistentImages = await _moveInputs(id, imagePaths, prefix: 'image');
    final item = GalleryItem(
      id: id,
      path: '',
      isPhoto: false,
      status: GalleryItemStatus.processing,
    );
    final outputPath = await _outputPathForJob(
      id,
      MediaProcessingJobType.timeburst,
    );
    final job = _MediaProcessingJob(
      itemId: id,
      type: MediaProcessingJobType.timeburst,
      sourcePaths: persistentImages,
      frameRate: frameRate,
      outputPath: outputPath,
      resolutionPreset: resolutionPreset,
      location: location,
    );
    await _persist(item, job);
    await _schedule(job);
    return EnqueuedMedia(item: item);
  }

  static Future<GalleryItem?> runJob(String itemId) async {
    final jobFile = await _jobFile(itemId);
    return MediaJobLock.protect('${jobFile.path}.lock', () async {
      if (!await jobFile.exists()) {
        return await _findGalleryItem(itemId);
      }

      var job = _MediaProcessingJob.fromJson(
        jsonDecode(await jobFile.readAsString()) as Map<String, dynamic>,
      );
      if (job.outputPath == null && job.type != MediaProcessingJobType.photo) {
        // Migrate jobs created before outputPath became part of the durable
        // job record. A stable path makes a retry safe after a process kill.
        job = job.copyWith(
          outputPath: await _outputPathForJob(itemId, job.type),
        );
        await _writeJobFile(jobFile, job);
      }
      GalleryItem? item = await _findGalleryItem(itemId);
      item ??= GalleryItem(
        id: itemId,
        path: job.type == MediaProcessingJobType.photo
            ? job.sourcePaths.first
            : '',
        isPhoto: job.type == MediaProcessingJobType.photo,
        status: GalleryItemStatus.processing,
      );
      if (item.status == GalleryItemStatus.success) {
        await _deleteJobInputs(job, keepPhoto: true);
        await _deleteIfExists(jobFile.path);
        return item;
      }

      try {
        final completed = await _process(job, item);

        var finalizedJob = job;
        if (job.type != MediaProcessingJobType.photo && !job.gallerySaved) {
          final saved = await StorageService.saveVideoToGallery(completed.path);
          if (!saved) {
            throw StateError('Video cihaz galerisine kaydedilemedi.');
          }
          finalizedJob = job.copyWith(gallerySaved: true);
          await _writeJobFile(jobFile, finalizedJob);
        }
        await PreferencesService.upsertGalleryItem(completed);
        await _deleteJobInputs(finalizedJob, keepPhoto: true);
        await _deleteIfExists(jobFile.path);
        return completed;
      } catch (error, stackTrace) {
        debugPrint('Background media processing failed: $error\n$stackTrace');
        final failed = item.copyWith(
          status: GalleryItemStatus.failed,
          errorMessage: _errorMessage(job.type, error),
        );
        await PreferencesService.upsertGalleryItem(failed);
        return failed;
      }
    });
  }

  static Future<void> runAllPendingJobs() async {
    final directory = await _jobsDirectory;
    final jobFiles = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList(growable: false);
    for (final jobFile in jobFiles) {
      await runJob(path.basenameWithoutExtension(jobFile.path));
    }
  }

  /// Runs pending jobs from the foreground isolate as a recovery path.
  /// WorkManager is still scheduled, but this also handles jobs that were
  /// stopped while encoding a long video and were left in `processing`.
  static Future<void> recoverPendingJobs() {
    final current = _recoveryInProgress;
    if (current != null) return current;

    final recovery = runAllPendingJobs();
    _recoveryInProgress = recovery.whenComplete(() {
      _recoveryInProgress = null;
    });
    return _recoveryInProgress!;
  }

  static Future<void> reschedulePendingJobs() async {
    final directory = await _jobsDirectory;
    final jobFiles = directory.listSync().whereType<File>().where(
      (file) => file.path.endsWith('.json'),
    );
    for (final jobFile in jobFiles) {
      final job = _MediaProcessingJob.fromJson(
        jsonDecode(await jobFile.readAsString()) as Map<String, dynamic>,
      );
      await _schedule(job);
    }
  }

  static Future<void> deleteItem(GalleryItem item) async {
    final jobFile = await _jobFile(item.id);
    await MediaJobLock.protect('${jobFile.path}.lock', () async {
      final latest = await _findGalleryItem(item.id) ?? item;
      if (await jobFile.exists()) {
        final job = _MediaProcessingJob.fromJson(
          jsonDecode(await jobFile.readAsString()) as Map<String, dynamic>,
        );
        await _deleteJobInputs(job);
        if (job.outputPath != null) {
          await _deleteIfExists(job.outputPath!);
          await _deleteIfExists('${job.outputPath}.thumb.jpg');
        }
        await _deleteIfExists(jobFile.path);
      }
      await _deleteIfExists(latest.path);
      if (latest.thumbnailPath != null) {
        await _deleteIfExists(latest.thumbnailPath!);
      }
      await PreferencesService.removeGalleryItem(item.id);
    });
    if (_workmanagerInitialized && Platform.isAndroid) {
      await Workmanager().cancelByUniqueName(_androidWorkName(item.id));
    }
  }

  static Future<GalleryItem> _process(
    _MediaProcessingJob job,
    GalleryItem item,
  ) async {
    switch (job.type) {
      case MediaProcessingJobType.photo:
        final result = await PhotoProcessingService.instance.process(
          XFile(job.sourcePaths.single),
          targetAspectRatio: job.targetAspectRatio!,
          saveToGallery: true,
          mirrorHorizontally: job.mirrorHorizontally,
          location: job.location,
        );
        if (!result.success) {
          throw StateError('Could not save the photo to the device gallery.');
        }
        return item.copyWith(
          path: result.path,
          status: GalleryItemStatus.success,
          clearError: true,
        );
      case MediaProcessingJobType.video:
        final output = job.audioPath == null
            ? await MediaMuxerService.finalizeVideoSegments(
                videoPaths: job.sourcePaths,
                outputPath: job.outputPath!,
                resolutionPreset: job.resolutionPreset,
                targetAspectRatio: job.targetAspectRatio,
                location: job.location,
              )
            : await MediaMuxerService.muxMultipleVideosAndAudio(
                videoPaths: job.sourcePaths,
                audioPath: job.audioPath!,
                outputPath: job.outputPath!,
                resolutionPreset: job.resolutionPreset,
                location: job.location,
              );
        if (output == null) {
          throw StateError('Could not combine video and audio.');
        }
        final thumbnail = await MediaMuxerService.generateThumbnail(
          output,
          thumbnailPath: '${job.outputPath}.thumb.jpg',
        );
        return item.copyWith(
          path: output,
          thumbnailPath: thumbnail,
          status: GalleryItemStatus.success,
          clearError: true,
        );
      case MediaProcessingJobType.timeburst:
        final output = await MediaMuxerService.compileImagesToVideo(
          imagePaths: job.sourcePaths,
          framerate: job.frameRate,
          outputPath: job.outputPath!,
          resolutionPreset: job.resolutionPreset,
          location: job.location,
        );
        if (output == null) {
          throw StateError('Could not create the timeburst video.');
        }
        final thumbnail = await MediaMuxerService.generateThumbnail(
          output,
          thumbnailPath: '${job.outputPath}.thumb.jpg',
        );
        return item.copyWith(
          path: output,
          thumbnailPath: thumbnail,
          status: GalleryItemStatus.success,
          clearError: true,
        );
    }
  }

  static Future<void> _persist(
    GalleryItem item,
    _MediaProcessingJob job,
  ) async {
    final jobFile = await _jobFile(job.itemId);
    await MediaJobLock.protect('${jobFile.path}.lock', () async {
      await _writeJobFile(jobFile, job);
      await PreferencesService.upsertGalleryItem(item);
    });
  }

  static Future<void> _writeJobFile(
    File jobFile,
    _MediaProcessingJob job,
  ) async {
    final temporaryFile = File(
      '${jobFile.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temporaryFile.writeAsString(jsonEncode(job.toJson()), flush: true);
    try {
      try {
        // POSIX rename replaces the destination atomically. This keeps the
        // job recoverable if the process is killed during the write.
        await temporaryFile.rename(jobFile.path);
      } on FileSystemException {
        // Windows is only relevant for local tests; it may reject replacing
        // an existing file, so retain a safe fallback for that platform.
        await _deleteIfExists(jobFile.path);
        await temporaryFile.rename(jobFile.path);
      }
    } finally {
      await _deleteIfExists(temporaryFile.path);
    }
  }

  static Future<void> _schedule(_MediaProcessingJob job) async {
    if (!_workmanagerInitialized) return;

    if (Platform.isAndroid) {
      await Workmanager().registerOneOffTask(
        _androidWorkName(job.itemId),
        _backgroundMediaTask,
        inputData: <String, dynamic>{'itemId': job.itemId},
        existingWorkPolicy: ExistingWorkPolicy.keep,
        constraints: Constraints(requiresStorageNotLow: true),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 10),
      );
    } else if (Platform.isIOS) {
      await Workmanager().registerProcessingTask(
        _iosProcessingTaskId,
        _iosProcessingTaskId,
        constraints: Constraints(requiresStorageNotLow: true),
      );
    }
  }

  static String _androidWorkName(String itemId) => 'media-processing-$itemId';

  static Future<GalleryItem?> _findGalleryItem(String id) async {
    final items = await PreferencesService.loadGalleryItems();
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  static Future<List<String>> _moveInputs(
    String itemId,
    List<String> sourcePaths, {
    required String prefix,
  }) async {
    final directory = Directory(
      path.join((await _jobsDirectory).path, '${itemId}_inputs'),
    );
    await directory.create(recursive: true);
    final movedPaths = <String>[];
    for (var index = 0; index < sourcePaths.length; index++) {
      final sourcePath = sourcePaths[index];
      final extension = path.extension(sourcePath);
      final destination = path.join(
        directory.path,
        '${prefix}_$index$extension',
      );
      await _moveFile(sourcePath, destination);
      movedPaths.add(destination);
    }
    return movedPaths;
  }

  static Future<void> _moveFile(String sourcePath, String destination) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
        'No media file was found to process.',
        sourcePath,
      );
    }
    await File(destination).parent.create(recursive: true);
    try {
      await source.rename(destination);
    } on FileSystemException {
      await source.copy(destination);
      await source.delete();
    }
  }

  static Future<void> _deleteJobInputs(
    _MediaProcessingJob job, {
    bool keepPhoto = false,
  }) async {
    if (!keepPhoto || job.type != MediaProcessingJobType.photo) {
      for (final sourcePath in job.sourcePaths) {
        await _deleteIfExists(sourcePath);
      }
    }
    if (job.audioPath != null) {
      await _deleteIfExists(job.audioPath!);
    }
    if (job.sourcePaths.isNotEmpty) {
      final parent = File(job.sourcePaths.first).parent;
      if (parent.path.contains('_inputs') && await parent.exists()) {
        await parent.delete(recursive: true);
      }
    }
  }

  static Future<void> _deleteIfExists(String filePath) async {
    if (filePath.isEmpty) return;
    final file = File(filePath);
    try {
      await file.delete();
    } on FileSystemException {
      // Another foreground/background worker may remove the same cleanup
      // target after it was discovered. Treat an already-missing file as a
      // successful, idempotent cleanup while preserving real I/O failures.
      if (await file.exists()) {
        rethrow;
      }
    }
  }

  static String _errorMessage(MediaProcessingJobType type, Object error) {
    final prefix = switch (type) {
      MediaProcessingJobType.photo => 'Could not process the photo.',
      MediaProcessingJobType.video => 'Could not process the video.',
      MediaProcessingJobType.timeburst => 'Could not process the timeburst.',
    };
    return '$prefix: $error';
  }

  static Future<Directory> get _jobsDirectory async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(documents.path, 'processing_jobs'));
    await directory.create(recursive: true);
    return directory;
  }

  static Future<Directory> get _mediaDirectory async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(documents.path, 'media'));
    await directory.create(recursive: true);
    return directory;
  }

  static Future<String> _outputPathForJob(
    String itemId,
    MediaProcessingJobType type,
  ) async {
    final directory = await _mediaDirectory;
    final prefix = switch (type) {
      MediaProcessingJobType.video => 'VID',
      MediaProcessingJobType.timeburst => 'TIMELAPSE',
      MediaProcessingJobType.photo => 'IMG',
    };
    return path.join(directory.path, '${prefix}_$itemId.mp4');
  }

  static Future<File> _jobFile(String itemId) async {
    return File(path.join((await _jobsDirectory).path, '$itemId.json'));
  }
}

class _MediaProcessingJob {
  const _MediaProcessingJob({
    required this.itemId,
    required this.type,
    required this.sourcePaths,
    this.audioPath,
    this.targetAspectRatio,
    this.mirrorHorizontally = false,
    this.outputPath,
    this.location,
    this.resolutionPreset = ResolutionPreset.max,
    this.gallerySaved = false,
    this.frameRate = 30,
  });

  final String itemId;
  final MediaProcessingJobType type;
  final List<String> sourcePaths;
  final String? audioPath;
  final double? targetAspectRatio;
  final bool mirrorHorizontally;
  final String? outputPath;
  final MediaLocation? location;
  final ResolutionPreset resolutionPreset;
  final bool gallerySaved;
  final int frameRate;

  Map<String, Object?> toJson() => <String, Object?>{
    'itemId': itemId,
    'type': type.name,
    'sourcePaths': sourcePaths,
    'audioPath': audioPath,
    'targetAspectRatio': targetAspectRatio,
    'mirrorHorizontally': mirrorHorizontally,
    'outputPath': outputPath,
    'location': location?.toJson(),
    'resolutionPreset': resolutionPreset.name,
    'gallerySaved': gallerySaved,
    'frameRate': frameRate,
  };

  _MediaProcessingJob copyWith({
    String? outputPath,
    ResolutionPreset? resolutionPreset,
    bool? gallerySaved,
  }) {
    return _MediaProcessingJob(
      itemId: itemId,
      type: type,
      sourcePaths: sourcePaths,
      audioPath: audioPath,
      targetAspectRatio: targetAspectRatio,
      mirrorHorizontally: mirrorHorizontally,
      outputPath: outputPath ?? this.outputPath,
      location: location,
      resolutionPreset: resolutionPreset ?? this.resolutionPreset,
      gallerySaved: gallerySaved ?? this.gallerySaved,
      frameRate: frameRate,
    );
  }

  factory _MediaProcessingJob.fromJson(Map<String, dynamic> json) {
    return _MediaProcessingJob(
      itemId: json['itemId'] as String,
      type: MediaProcessingJobType.values.firstWhere(
        (type) => type.name == json['type'],
      ),
      sourcePaths: (json['sourcePaths'] as List<dynamic>).cast<String>(),
      audioPath: json['audioPath'] as String?,
      targetAspectRatio: (json['targetAspectRatio'] as num?)?.toDouble(),
      mirrorHorizontally: json['mirrorHorizontally'] as bool? ?? false,
      outputPath: json['outputPath'] as String?,
      location: (json['location'] as Map<String, dynamic>?) == null
          ? null
          : MediaLocation.fromJson((json['location'] as Map<String, dynamic>)),
      resolutionPreset: ResolutionPreset.values.firstWhere(
        (preset) => preset.name == json['resolutionPreset'],
        orElse: () => ResolutionPreset.max,
      ),
      gallerySaved: json['gallerySaved'] as bool? ?? false,
      frameRate: json['frameRate'] as int? ?? 30,
    );
  }
}
