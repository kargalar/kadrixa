import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/capture_mode.dart';
import '../models/gallery_item.dart';

class PreferencesService {
  static bool isTestMode = false;
  static Map<String, dynamic> testData = {};
  static List<GalleryItem> testGalleryItems = [];

  @visibleForTesting
  static String? documentsDirectoryPathOverrideForTesting;

  static const String _fileName = 'settings_prefs.json';
  static const String _galleryFileName = 'gallery_metadata.json';
  static const Duration _galleryMutexRetryDelay = Duration(milliseconds: 20);
  static const Duration _galleryMutexTimeout = Duration(seconds: 10);
  static const Duration _staleGalleryMutexAge = Duration(minutes: 1);
  static Future<void> _mutationQueue = Future<void>.value();
  static Future<void> _galleryMutationQueue = Future<void>.value();
  static int _galleryTemporaryFileSequence = 0;

  static Future<Directory> get _documentsDirectory async {
    final override = documentsDirectoryPathOverrideForTesting;
    if (override != null) {
      final directory = Directory(override);
      await directory.create(recursive: true);
      return directory;
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<File> get _file async {
    final directory = await _documentsDirectory;
    return File('${directory.path}/$_fileName');
  }

  static Future<File> get _galleryFile async {
    final directory = await _documentsDirectory;
    return File('${directory.path}/$_galleryFileName');
  }

  static Future<Map<String, dynamic>> _loadAll() async {
    if (isTestMode) return testData;
    try {
      final file = await _file;
      if (await file.exists()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Error loading preferences: $e");
    }
    return {};
  }

  static Future<void> _saveAll(Map<String, dynamic> data) async {
    if (isTestMode) {
      testData = data;
      return;
    }
    try {
      final file = await _file;
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Error saving preferences: $e");
    }
  }

  static Future<void> _updateAll(
    void Function(Map<String, dynamic> data) mutate,
  ) {
    if (isTestMode) {
      final data = Map<String, dynamic>.from(testData);
      mutate(data);
      testData = data;
      return Future<void>.value();
    }

    final operation = _mutationQueue.then((_) async {
      final data = Map<String, dynamic>.from(await _loadAll());
      mutate(data);
      await _saveAll(data);
    });
    _mutationQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static Future<void> saveCaptureMode(CaptureMode mode) async {
    await _updateAll((data) => data['captureMode'] = mode.name);
  }

  static Future<CaptureMode> loadCaptureMode() async {
    final data = await _loadAll();
    final modeName = data['captureMode'];
    if (modeName != null) {
      return CaptureMode.values.firstWhere(
        (e) => e.name == modeName,
        orElse: () => CaptureMode.photo,
      );
    }
    return CaptureMode.photo;
  }

  static Future<void> saveFlashMode(FlashMode mode) async {
    await _updateAll((data) => data['flashMode'] = mode.name);
  }

  static Future<FlashMode> loadFlashMode() async {
    final data = await _loadAll();
    final modeName = data['flashMode'];
    if (modeName != null) {
      return FlashMode.values.firstWhere(
        (e) => e.name == modeName,
        orElse: () => FlashMode.auto,
      );
    }
    return FlashMode.auto;
  }

  static Future<void> saveResolution(ResolutionPreset preset) async {
    await _updateAll((data) => data['resolution'] = preset.name);
  }

  static Future<ResolutionPreset> loadResolution() async {
    final data = await _loadAll();
    final presetName = data['resolution'];
    if (presetName != null) {
      return ResolutionPreset.values.firstWhere(
        (e) => e.name == presetName,
        orElse: () => ResolutionPreset.max,
      );
    }
    return ResolutionPreset.max;
  }

  static Future<void> saveAspectRatio(double ratio) async {
    await _updateAll((data) => data['aspectRatio'] = ratio);
  }

  static Future<double> loadAspectRatio() async {
    final data = await _loadAll();
    final ratio = data['aspectRatio'];
    if (ratio != null) {
      return (ratio as num).toDouble();
    }
    return 4 / 3;
  }

  static Future<void> saveSelectedMicrophone(
    String? deviceId,
    String? label,
  ) async {
    await _updateAll((data) {
      data['microphoneId'] = deviceId;
      data['microphoneLabel'] = label;
    });
  }

  static Future<Map<String, String?>> loadSelectedMicrophone() async {
    final data = await _loadAll();
    return {
      'id': data['microphoneId'] as String?,
      'label': data['microphoneLabel'] as String?,
    };
  }

  static Future<void> saveAudioWaveformVisible(bool isVisible) async {
    await _updateAll((data) => data['audioWaveformVisible'] = isVisible);
  }

  static Future<bool> loadAudioWaveformVisible() async {
    final data = await _loadAll();
    return data['audioWaveformVisible'] as bool? ?? true;
  }

  static Future<void> saveSelectedCameraId(String cameraId) async {
    await _updateAll((data) => data['selectedCameraId'] = cameraId);
  }

  static Future<String?> loadSelectedCameraId() async {
    final data = await _loadAll();
    return data['selectedCameraId'] as String?;
  }

  static Future<void> saveGalleryItems(List<GalleryItem> items) async {
    if (isTestMode) {
      testGalleryItems = List<GalleryItem>.from(items);
      return;
    }
    await _queueGalleryMutation(
      () => _writeGalleryItems(List<GalleryItem>.from(items)),
    );
  }

  static Future<void> upsertGalleryItem(GalleryItem item) async {
    if (isTestMode) {
      final items = List<GalleryItem>.from(testGalleryItems);
      final index = items.indexWhere((candidate) => candidate.id == item.id);
      if (index == -1) {
        items.add(item);
      } else {
        items[index] = item;
      }
      testGalleryItems = items;
      return;
    }

    await _queueGalleryMutation(() async {
      final items = await _readGalleryItems();
      final index = items.indexWhere((candidate) => candidate.id == item.id);
      if (index == -1) {
        items.add(item);
      } else {
        items[index] = item;
      }
      await _writeGalleryItems(items);
    });
  }

  static Future<void> removeGalleryItem(String id) async {
    if (isTestMode) {
      testGalleryItems = testGalleryItems
          .where((item) => item.id != id)
          .toList(growable: false);
      return;
    }

    await _queueGalleryMutation(() async {
      final items = await _readGalleryItems();
      items.removeWhere((item) => item.id == id);
      await _writeGalleryItems(items);
    });
  }

  static Future<List<GalleryItem>> loadGalleryItems() async {
    if (isTestMode) {
      return List<GalleryItem>.from(testGalleryItems);
    }
    try {
      return await _readGalleryItems();
    } catch (e) {
      debugPrint("Error loading gallery items: $e");
    }
    return [];
  }

  static Future<void> _queueGalleryMutation(Future<void> Function() mutate) {
    final operation = _galleryMutationQueue.then((_) async {
      final galleryFile = await _galleryFile;
      await _withGalleryMutex(galleryFile, mutate);
    });
    _galleryMutationQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  static Future<void> _withGalleryMutex(
    File galleryFile,
    Future<void> Function() mutate,
  ) async {
    final mutexFile = File('${galleryFile.path}.mutex');
    final deadline = DateTime.now().add(_galleryMutexTimeout);

    while (true) {
      try {
        await mutexFile.create(exclusive: true);
      } on FileSystemException catch (error) {
        // The owner may remove the lock before our exists check completes.
        if (error is! PathExistsException && !await mutexFile.exists()) {
          rethrow;
        }
        if (DateTime.now().isAfter(deadline)) {
          if (await _deleteStaleGalleryMutex(mutexFile)) {
            continue;
          }
          throw TimeoutException(
            'Timed out waiting to update ${galleryFile.path}',
            _galleryMutexTimeout,
          );
        }
        await Future<void>.delayed(_galleryMutexRetryDelay);
        continue;
      }

      try {
        await mutexFile.writeAsString(
          '$pid\n${DateTime.now().toUtc().toIso8601String()}',
          flush: true,
        );
        await mutate();
        return;
      } finally {
        try {
          await mutexFile.delete();
        } on FileSystemException {
          if (await mutexFile.exists()) {
            rethrow;
          }
        }
      }
    }
  }

  static Future<bool> _deleteStaleGalleryMutex(File mutexFile) async {
    try {
      final modifiedAt = await mutexFile.lastModified();
      if (DateTime.now().difference(modifiedAt) < _staleGalleryMutexAge) {
        return false;
      }
      await mutexFile.delete();
      return true;
    } on FileSystemException {
      return !await mutexFile.exists();
    }
  }

  static Future<List<GalleryItem>> _readGalleryItems() async {
    final file = await _galleryFile;
    if (!await file.exists()) return <GalleryItem>[];

    final content = await file.readAsString();
    if (content.trim().isEmpty) return <GalleryItem>[];

    final encodedItems = jsonDecode(content) as List<dynamic>;
    final loaded = <GalleryItem>[];
    for (final encoded in encodedItems) {
      final item = GalleryItem.fromJson(encoded as Map<String, dynamic>);
      if (item.status != GalleryItemStatus.success ||
          File(item.path).existsSync()) {
        loaded.add(item);
      }
    }
    return loaded;
  }

  static Future<void> _writeGalleryItems(List<GalleryItem> items) async {
    File? temporaryFile;
    try {
      final file = await _galleryFile;
      final sequence = _galleryTemporaryFileSequence++;
      temporaryFile = File(
        '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.'
        '$sequence.tmp',
      );
      await temporaryFile.writeAsString(
        jsonEncode(items.map((item) => item.toJson()).toList()),
        flush: true,
      );
      try {
        await temporaryFile.rename(file.path);
      } on FileSystemException {
        if (!Platform.isWindows) rethrow;
        if (await file.exists()) await file.delete();
        await temporaryFile.rename(file.path);
      }
    } catch (error) {
      debugPrint('Error saving gallery items: $error');
      rethrow;
    } finally {
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }
}
