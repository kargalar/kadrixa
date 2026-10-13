import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../constants/app_brand.dart';
import '../models/media_location.dart';
import '../models/capture_geometry.dart';

class MediaProcessingException implements Exception {
  const MediaProcessingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MediaMuxerService {
  static const _mediaChannel = MethodChannel(
    '${AppBrand.applicationId}/media_pipeline',
  );
  static Future<Directory> get _outputDirectory async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(documents.path, 'media'));
    await directory.create(recursive: true);
    return directory;
  }

  /// Merges a video file and an audio file into a single output MP4 file.
  /// Returns the path to the combined file if successful, otherwise null.
  /// The output file is kept on disk for in-app gallery playback.
  static Future<String?> muxAudioVideo({
    required String videoPath,
    required String audioPath,
    required String outputPath,
    ResolutionPreset? resolutionPreset,
    MediaLocation? location,
  }) async {
    try {
      if (await _hasUsableFile(outputPath)) return outputPath;

      final temporaryOutputPath = '$outputPath.processing';
      await _deleteIfExists(temporaryOutputPath);

      final String command =
          '-y -i "$videoPath" -i "$audioPath" ${_videoEncodingArguments(resolutionPreset)} -c:a aac -map 0:v:0 -map 1:a:0 ${_locationMetadataArguments(location)} -f mp4 "$temporaryOutputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        await _finalizeOutput(temporaryOutputPath, outputPath);
        return outputPath;
      } else {
        final failStackTrace = await session.getFailStackTrace();
        debugPrint(
          "FFmpeg merge failed with state: ${await session.getState()} and return code: $returnCode",
        );
        debugPrint("Fail StackTrace: $failStackTrace");
        throw MediaProcessingException(
          _failureMessage(
            operation: 'Combining video and audio',
            returnCode: '$returnCode',
            details: failStackTrace,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error during muxing: $e");
      rethrow;
    }
  }

  /// Merges multiple video files and a single audio file into a single output MP4 file.
  /// Returns the path to the combined file if successful, otherwise null.
  static Future<String?> muxMultipleVideosAndAudio({
    required List<String> videoPaths,
    required String audioPath,
    required String outputPath,
    ResolutionPreset? resolutionPreset,
    MediaLocation? location,
  }) async {
    if (videoPaths.isEmpty) return null;
    if (videoPaths.length == 1) {
      return muxAudioVideo(
        videoPath: videoPaths.first,
        audioPath: audioPath,
        outputPath: outputPath,
        resolutionPreset: resolutionPreset,
        location: location,
      );
    }

    try {
      if (await _hasUsableFile(outputPath)) return outputPath;

      // Create inputs.txt file for concatenation
      final File inputsFile = File('$outputPath.inputs.txt');
      final StringBuffer buffer = StringBuffer();
      for (final path in videoPaths) {
        // FFmpeg concat format requires forward slashes
        final cleanPath = path.replaceAll('\\', '/');
        buffer.writeln("file '$cleanPath'");
      }
      await inputsFile.writeAsString(buffer.toString());

      final String concatVideoPath = '$outputPath.concat.mp4';
      final String temporaryOutputPath = '$outputPath.processing';
      await _deleteIfExists(concatVideoPath);
      await _deleteIfExists(temporaryOutputPath);

      // Step 1: Concatenate video segments
      final String concatCommand =
          '-y -f concat -safe 0 -i "${inputsFile.path}" -c copy "$concatVideoPath"';

      final concatSession = await FFmpegKit.execute(concatCommand);
      final concatReturnCode = await concatSession.getReturnCode();

      if (!ReturnCode.isSuccess(concatReturnCode)) {
        final details = await concatSession.getFailStackTrace();
        throw MediaProcessingException(
          _failureMessage(
            operation: 'Combining video segments',
            returnCode: '$concatReturnCode',
            details: details,
          ),
        );
      }

      // Step 2: Mux concatenated video with audio
      final String muxCommand =
          '-y -i "$concatVideoPath" -i "$audioPath" ${_videoEncodingArguments(resolutionPreset)} -c:a aac -map 0:v:0 -map 1:a:0 ${_locationMetadataArguments(location)} -f mp4 "$temporaryOutputPath"';

      final muxSession = await FFmpegKit.execute(muxCommand);
      final muxReturnCode = await muxSession.getReturnCode();

      if (ReturnCode.isSuccess(muxReturnCode)) {
        await _finalizeOutput(temporaryOutputPath, outputPath);
        return outputPath;
      } else {
        final details = await muxSession.getFailStackTrace();
        throw MediaProcessingException(
          _failureMessage(
            operation: 'Combining video and audio',
            returnCode: '$muxReturnCode',
            details: details,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error during multiple video muxing: $e");
      rethrow;
    } finally {
      await _deleteIfExists('$outputPath.inputs.txt');
      await _deleteIfExists('$outputPath.concat.mp4');
    }
  }

  /// Finalizes recordings that already contain synchronized audio and video.
  /// A single recording is moved into the media directory without encoding.
  /// FFmpeg is used for segment joining or location metadata.
  static Future<String?> finalizeVideoSegments({
    required List<String> videoPaths,
    required String outputPath,
    required ResolutionPreset resolutionPreset,
    double? targetAspectRatio,
    MediaLocation? location,
  }) async {
    if (videoPaths.isEmpty) return null;
    if (await _hasUsableFile(outputPath)) return outputPath;

    // Inspect displayed dimensions after the camera's orientation metadata.
    // Crop in that coordinate system, exactly as the viewfinder does.
    final sourceSize =
        targetAspectRatio == null &&
            videoPaths.length == 1 &&
            resolutionPreset == ResolutionPreset.max
        ? null
        : displayedVideoSize(await _inspectVideo(videoPaths.first));
    final outputSize = sourceSize == null
        ? sourceSize
        : CaptureGeometry.videoSize(
            sourceSize.width,
            sourceSize.height,
            targetAspectRatio,
            resolutionPreset,
          );
    final needsTransform = sourceSize != outputSize;
    final needsFfmpeg =
        videoPaths.length > 1 || location != null || needsTransform;
    if (!needsFfmpeg) {
      final source = File(videoPaths.single);
      if (!await _hasUsableFile(source.path)) return null;
      await File(outputPath).parent.create(recursive: true);
      try {
        await source.rename(outputPath);
      } on FileSystemException {
        await source.copy(outputPath);
        await source.delete();
      }
      return outputPath;
    }

    final temporaryOutputPath = '$outputPath.processing';
    final inputsFile = File('$outputPath.inputs.txt');
    final normalizedPaths = <String>[];
    await _deleteIfExists(temporaryOutputPath);
    try {
      String inputArguments;
      if (videoPaths.length == 1 && !needsTransform) {
        inputArguments = '-i "${videoPaths.single}"';
      } else {
        // Lens switches may change dimensions, rotation and encoder parameters.
        // Normalize each segment before concatenating; copying incompatible
        // bitstreams can produce a file that freezes at the first lens switch.
        final size = outputSize!;
        final width = size.width;
        final height = size.height;
        for (var index = 0; index < videoPaths.length; index++) {
          final normalized = '$outputPath.segment_$index.mp4';
          normalizedPaths.add(normalized);
          final segmentSize = displayedVideoSize(
            await _inspectVideo(videoPaths[index]),
          );
          final crop = targetAspectRatio == null
              ? segmentSize
              : CaptureGeometry.cropSize(
                  segmentSize.width,
                  segmentSize.height,
                  targetAspectRatio,
                );
          final filter =
              'crop=${crop.width}:${crop.height},'
              'scale=$width:$height:force_original_aspect_ratio=increase,'
              'crop=$width:$height,setsar=1,fps=30';
          final session = await FFmpegKit.execute(
            '-y -i "${videoPaths[index]}" -map 0:v:0 -map 0:a? '
            '-vf "$filter" -c:v libx264 -preset veryfast -crf 20 '
            '-pix_fmt yuv420p -c:a aac -ar 48000 -ac 1 '
            '-af "aresample=async=1:first_pts=0" -video_track_timescale 90000 '
            '-metadata:s:v:0 rotate=0 "$normalized"',
          );
          if (!ReturnCode.isSuccess(await session.getReturnCode())) {
            throw const MediaProcessingException(
              'Could not process the video frame.',
            );
          }
        }
        final contents = StringBuffer();
        for (final videoPath in normalizedPaths) {
          final cleanPath = videoPath.replaceAll('\\', '/');
          contents.writeln("file '$cleanPath'");
        }
        await inputsFile.writeAsString(contents.toString());
        inputArguments = '-f concat -safe 0 -i "${inputsFile.path}"';
      }

      final command =
          '-y $inputArguments -map 0:v:0 -map 0:a? '
          '-c:v copy -c:a copy '
          '${_locationMetadataArguments(location)} -movflags +faststart '
          '-f mp4 "$temporaryOutputPath"';
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        await _finalizeOutput(temporaryOutputPath, outputPath);
        return outputPath;
      }

      final details = await session.getAllLogsAsString();
      throw MediaProcessingException(
        _failureMessage(
          operation: 'Finishing video recording',
          returnCode: '$returnCode',
          details: details,
        ),
      );
    } catch (error) {
      debugPrint('Error finalizing recorded video: $error');
      rethrow;
    } finally {
      await _deleteIfExists(inputsFile.path);
      for (final normalized in normalizedPaths) {
        await _deleteIfExists(normalized);
      }
    }
  }

  /// Generates a thumbnail image from a video file using FFmpeg.
  /// Returns the path to the generated thumbnail, or null on failure.
  static Future<String?> generateThumbnail(
    String videoPath, {
    String? thumbnailPath,
  }) async {
    try {
      final Directory outputDirectory = await _outputDirectory;
      final String thumbPath =
          thumbnailPath ??
          '${outputDirectory.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
      if (await _hasUsableFile(thumbPath)) return thumbPath;

      // Short Timeburst videos may contain less than half a second of footage.
      final String command =
          '-y -i "$videoPath" -vframes 1 -q:v 2 "$thumbPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode) && File(thumbPath).existsSync()) {
        return thumbPath;
      }
      return null;
    } catch (e) {
      debugPrint("Error generating thumbnail: $e");
      return null;
    }
  }

  /// Compiles a sequence of images into a video using FFmpeg.
  /// Returns the path to the compiled video if successful, otherwise null.
  static Future<String?> compileImagesToVideo({
    required List<String> imagePaths,
    int framerate = 30,
    required String outputPath,
    ResolutionPreset? resolutionPreset,
    MediaLocation? location,
  }) async {
    if (imagePaths.isEmpty) return null;
    if (framerate <= 0) throw ArgumentError.value(framerate, 'framerate');

    try {
      if (await _hasUsableFile(outputPath)) return outputPath;

      // Create inputs.txt file for image concatenation
      final File inputsFile = File('$outputPath.inputs.txt');
      final StringBuffer buffer = StringBuffer();

      // To create a video from images with a specific framerate using concat demuxer:
      // each image gets a duration based on the framerate (duration = 1.0 / framerate)
      final String durationStr = (1.0 / framerate).toStringAsFixed(5);

      for (final path in imagePaths) {
        final cleanPath = path.replaceAll('\\', '/');
        buffer.writeln("file '$cleanPath'");
        buffer.writeln("duration $durationStr");
      }
      // FFmpeg concat demuxer documentation recommends adding the last file again without duration
      if (imagePaths.isNotEmpty) {
        final cleanPath = imagePaths.last.replaceAll('\\', '/');
        buffer.writeln("file '$cleanPath'");
      }

      await inputsFile.writeAsString(buffer.toString());

      final String temporaryOutputPath = '$outputPath.processing';
      await _deleteIfExists(temporaryOutputPath);

      // Use concat demuxer to compile images
      final String command =
          '-y -f concat -safe 0 -i "${inputsFile.path}" ${_videoEncodingArguments(resolutionPreset, encodeByDefault: true)} -r $framerate -frames:v ${imagePaths.length} -pix_fmt yuv420p ${_locationMetadataArguments(location)} -f mp4 "$temporaryOutputPath"';

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        await _finalizeOutput(temporaryOutputPath, outputPath);
        return outputPath;
      } else {
        final failStackTrace = await session.getFailStackTrace();
        debugPrint("FFmpeg image compilation failed. Return code: $returnCode");
        debugPrint("Fail StackTrace: $failStackTrace");
        throw MediaProcessingException(
          _failureMessage(
            operation: 'Creating timeburst video',
            returnCode: '$returnCode',
            details: failStackTrace,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error during image compilation: $e");
      rethrow;
    } finally {
      await _deleteIfExists('$outputPath.inputs.txt');
    }
  }

  static Future<bool> _hasUsableFile(String filePath) async {
    final file = File(filePath);
    try {
      return await file.exists() && await file.length() > 0;
    } on FileSystemException {
      return false;
    }
  }

  @visibleForTesting
  static ({int width, int height}) displayedVideoSize(
    Map<dynamic, dynamic> properties,
  ) {
    int number(Object? value) => num.tryParse('$value')?.round() ?? 0;
    var width = number(properties['width']);
    var height = number(properties['height']);
    final tags = properties['tags'];
    var rotation = properties['rotation'] != null
        ? number(properties['rotation'])
        : tags is Map
        ? number(tags['rotate'])
        : 0;
    final sideData = properties['side_data_list'];
    if (sideData is List) {
      for (final entry in sideData) {
        if (entry is Map && entry['rotation'] != null) {
          rotation = number(entry['rotation']);
          break;
        }
      }
    }
    if (rotation.abs() % 180 == 90) {
      (width, height) = (height, width);
    }
    width -= width % 2;
    height -= height % 2;
    if (width <= 0 || height <= 0) {
      throw const MediaProcessingException('Invalid video dimensions.');
    }
    return (width: width, height: height);
  }

  static Future<Map<dynamic, dynamic>> _inspectVideo(String videoPath) async {
    if (Platform.isAndroid) {
      return await _mediaChannel.invokeMapMethod('inspectVideo', {
            'path': videoPath,
          }) ??
          {};
    }
    final probe = await FFprobeKit.executeWithArguments([
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=width,height:stream_tags=rotate:stream_side_data=rotation',
      '-of',
      'json',
      videoPath,
    ]);
    if (!ReturnCode.isSuccess(await probe.getReturnCode())) {
      throw const MediaProcessingException('Could not read video dimensions.');
    }
    final information = jsonDecode(await probe.getOutput() ?? '{}');
    final streams = information['streams'] as List<dynamic>?;
    if (streams == null || streams.isEmpty) {
      throw const MediaProcessingException('Could not read video dimensions.');
    }
    return streams.first as Map;
  }

  static String _videoEncodingArguments(
    ResolutionPreset? preset, {
    bool encodeByDefault = false,
  }) {
    final height = switch (preset) {
      ResolutionPreset.low => 240,
      ResolutionPreset.medium => 480,
      ResolutionPreset.high => 720,
      ResolutionPreset.veryHigh => 1080,
      ResolutionPreset.ultraHigh => 2160,
      ResolutionPreset.max || null => null,
    };
    if (height == null && !encodeByDefault) return '-c:v copy';
    final scale = height == null ? '' : '-vf "scale=-2:$height" ';
    return '$scale-c:v libx264 -preset veryfast -crf 23';
  }

  static Future<void> _finalizeOutput(
    String temporaryOutputPath,
    String outputPath,
  ) async {
    if (!await _hasUsableFile(temporaryOutputPath)) {
      throw const MediaProcessingException(
        'FFmpeg reported success, but no video output was created.',
      );
    }
    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);
    if (await _hasUsableFile(outputPath)) {
      await _deleteIfExists(temporaryOutputPath);
      return;
    }
    await File(temporaryOutputPath).rename(outputPath);
  }

  static Future<void> _deleteIfExists(String filePath) async {
    final file = File(filePath);
    try {
      await file.delete();
    } on FileSystemException {
      if (await file.exists()) rethrow;
    }
  }

  static String _failureMessage({
    required String operation,
    required String returnCode,
    String? details,
  }) {
    final normalizedDetails = details?.trim();
    final suffix = normalizedDetails == null || normalizedDetails.isEmpty
        ? ''
        : '\n${normalizedDetails.length > 1500 ? normalizedDetails.substring(0, 1500) : normalizedDetails}';
    return '$operation failed (FFmpeg code: $returnCode).$suffix';
  }

  static String _locationMetadataArguments(MediaLocation? location) {
    if (location == null) return '';

    final iso6709 = _toIso6709(location);
    return '-metadata location="$iso6709" '
        '-metadata com.apple.quicktime.location.ISO6709="$iso6709"';
  }

  static String _toIso6709(MediaLocation location) {
    String coordinate(double value, String positive, String negative) {
      final sign = value >= 0 ? positive : negative;
      return '$sign${value.abs().toStringAsFixed(6)}';
    }

    return '${coordinate(location.latitude, '+', '-')}'
        '${coordinate(location.longitude, '+', '-')}/';
  }
}
