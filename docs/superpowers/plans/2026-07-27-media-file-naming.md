# Media File Naming Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Save photos, videos, and timeburst videos with readable, sortable, media-specific names.

**Architecture:** A focused Dart utility owns the file-name contract and accepts an injectable timestamp for deterministic tests. Photo enqueueing and both FFmpeg output paths consume that utility; Android's native photo gallery writer preserves the already-generated source name so the application copy and gallery copy remain consistent.

**Tech Stack:** Flutter, Dart, `path`, Android Kotlin, Flutter test

## Global Constraints

- Photo names must use `IMG_yyyyMMdd_HHmmss_SSS.jpg`.
- Normal video names must use `VID_yyyyMMdd_HHmmss_SSS.mp4`.
- Timeburst video names must use `TIMELAPSE_yyyyMMdd_HHmmss_SSS.mp4`.
- Timestamps use the device's local time.
- Existing background processing, gallery saving, FFmpeg, and error behavior must remain unchanged.
- Old media files are not renamed.
- No new package dependency is introduced.

---

## File Structure

- `lib/utils/media_file_name.dart`: Owns media kinds and deterministic file-name generation.
- `test/media_file_name_test.dart`: Verifies exact names for every media kind.
- `lib/services/background_media_processing_service.dart`: Names the persistent photo before processing and gallery export.
- `lib/services/media_muxer_service.dart`: Names normal and timeburst video outputs.
- `android/app/src/main/kotlin/com/example/camerapro/NativePhotoProcessor.kt`: Reuses the persistent photo's name when inserting the gallery copy.

### Task 1: Central media name contract and save-flow wiring

**Files:**

- Create: `lib/utils/media_file_name.dart`
- Create: `test/media_file_name_test.dart`
- Modify: `lib/services/background_media_processing_service.dart`
- Modify: `lib/services/media_muxer_service.dart`
- Modify: `android/app/src/main/kotlin/com/example/camerapro/NativePhotoProcessor.kt`

**Interfaces:**

- Produces: `enum MediaFileType { photo, video, timelapse }`
- Produces: `MediaFileName.create(MediaFileType type, {DateTime? timestamp}) -> String`
- Consumes: `path.basename(source.path)` in the Android native photo gallery writer.

- [ ] **Step 1: Write the failing naming tests**

Create `test/media_file_name_test.dart`:

```dart
import 'package:camerapro/utils/media_file_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaFileName', () {
    final timestamp = DateTime(2026, 7, 27, 14, 30, 52, 123);

    test('creates a sortable photo name', () {
      expect(
        MediaFileName.create(
          MediaFileType.photo,
          timestamp: timestamp,
        ),
        'IMG_20260727_143052_123.jpg',
      );
    });

    test('creates a sortable video name', () {
      expect(
        MediaFileName.create(
          MediaFileType.video,
          timestamp: timestamp,
        ),
        'VID_20260727_143052_123.mp4',
      );
    });

    test('creates a sortable timeburst name', () {
      expect(
        MediaFileName.create(
          MediaFileType.timelapse,
          timestamp: timestamp,
        ),
        'TIMELAPSE_20260727_143052_123.mp4',
      );
    });
  });
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```powershell
flutter test test/media_file_name_test.dart
```

Expected: FAIL because `lib/utils/media_file_name.dart` and its public API do not exist.

- [ ] **Step 3: Implement the minimal name generator**

Create `lib/utils/media_file_name.dart`:

```dart
enum MediaFileType { photo, video, timelapse }

abstract final class MediaFileName {
  static String create(
    MediaFileType type, {
    DateTime? timestamp,
  }) {
    final value = timestamp ?? DateTime.now();
    final date =
        '${_pad(value.year, 4)}${_pad(value.month)}${_pad(value.day)}';
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
```

- [ ] **Step 4: Run the focused test and verify GREEN**

Run:

```powershell
flutter test test/media_file_name_test.dart
```

Expected: all three tests PASS.

- [ ] **Step 5: Wire photo and video outputs to the contract**

In `lib/services/background_media_processing_service.dart`, import
`../utils/media_file_name.dart` and replace the persistent photo basename with:

```dart
final persistentPath = path.join(
  mediaDirectory.path,
  MediaFileName.create(MediaFileType.photo),
);
```

In `lib/services/media_muxer_service.dart`, import
`../utils/media_file_name.dart`. Replace both normal video output basenames
with:

```dart
path.join(
  outputDirectory.path,
  MediaFileName.create(MediaFileType.video),
)
```

Replace the timeburst output basename with:

```dart
path.join(
  outputDirectory.path,
  MediaFileName.create(MediaFileType.timelapse),
)
```

Do not change temporary concat lists, intermediate video names, or thumbnail
names because they are not user-visible saved media.

In `NativePhotoProcessor.kt`, compute the preferred gallery name before any
temporary crop file is created:

```kotlin
val displayName = source.name
```

Pass `displayName` through `saveToGallery`, `saveToModernMediaStore`, and
`saveToLegacyGallery`, and use it instead of calling `createDisplayName()`.
Delete the now-unused `createDisplayName()` method and its
`SimpleDateFormat`, `Date`, and `Locale` imports.

- [ ] **Step 6: Format and run focused verification**

Run:

```powershell
dart format lib/utils/media_file_name.dart test/media_file_name_test.dart lib/services/background_media_processing_service.dart lib/services/media_muxer_service.dart
flutter test test/media_file_name_test.dart test/photo_processing_service_test.dart
flutter analyze
```

Expected: formatting completes, tests PASS, and analysis reports no new issues.

- [ ] **Step 7: Run the complete Flutter test suite**

Run:

```powershell
flutter test
```

Expected: all existing and new tests PASS.

- [ ] **Step 8: Commit the implementation**

Stage only the files owned by this change:

```powershell
git add -- lib/utils/media_file_name.dart test/media_file_name_test.dart lib/services/background_media_processing_service.dart lib/services/media_muxer_service.dart android/app/src/main/kotlin/com/example/camerapro/NativePhotoProcessor.kt
git commit -m "feat: name saved media consistently"
```

Before committing, inspect the staged diff to ensure unrelated user changes in
the already-modified service files are not accidentally included. If the
working tree makes a clean isolated commit impossible, leave the verified
implementation uncommitted and report that explicitly instead of staging
unrelated changes.
