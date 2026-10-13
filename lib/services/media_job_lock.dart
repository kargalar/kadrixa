import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import '../constants/app_brand.dart';

/// Serializes foreground and WorkManager engines without blocking the UI thread.
class MediaJobLock {
  static const _channel = MethodChannel(
    '${AppBrand.applicationId}/media_pipeline',
  );
  static const _retryDelay = Duration(milliseconds: 100);
  static final Map<String, Future<void>> _queues = {};

  static Future<T> protect<T>(String lockPath, Future<T> Function() action) {
    final previous = _queues[lockPath] ?? Future<void>.value();
    final operation = previous.then((_) => _protect(lockPath, action));
    final tail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[lockPath] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_queues[lockPath], tail)) _queues.remove(lockPath);
      }),
    );
    return operation;
  }

  static Future<T> _protect<T>(
    String lockPath,
    Future<T> Function() action,
  ) async {
    if (Platform.isAndroid) {
      String? token;
      while (token == null) {
        token = await _channel.invokeMethod<String>('tryAcquireJobLock', {
          'path': lockPath,
        });
        if (token == null) await Future<void>.delayed(_retryDelay);
      }
      try {
        return await action();
      } finally {
        await _channel.invokeMethod<void>('releaseJobLock', {'token': token});
      }
    }

    final handle = await File(lockPath).open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.blockingExclusive);
      return await action();
    } finally {
      await handle.close();
    }
  }
}
