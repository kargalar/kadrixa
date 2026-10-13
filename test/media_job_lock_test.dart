import 'dart:async';
import 'dart:io';

import 'package:camerapro/services/media_job_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes jobs and releases the lock after failure', () async {
    final directory = await Directory.systemTemp.createTemp('media-lock-test');
    final lockPath = '${directory.path}/job.lock';
    final gate = Completer<void>();
    final calls = <int>[];
    final first = MediaJobLock.protect(lockPath, () async {
      calls.add(1);
      await gate.future;
      throw StateError('intentional failure');
    });
    final failure = expectLater(first, throwsStateError);
    final second = MediaJobLock.protect(lockPath, () async => calls.add(2));
    while (calls.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(calls, [1]);
    gate.complete();
    await failure;
    await second;
    expect(calls, [1, 2]);
    await File(lockPath).delete();
    await directory.delete();
  });
}
