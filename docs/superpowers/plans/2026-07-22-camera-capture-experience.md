# Camera Capture Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose every directly accessible rear lens, make audio levels readable, acknowledge captures immediately, silently finish successful saves, and restore all camera choices across launches.

**Architecture:** Keep `CameraService` as the controller owner, but add a small metadata model/classifier for rear lenses and serialize JSON preference mutations. Extract audio visualization and shutter feedback into focused widgets. Optimize JPEG cropping by reading dimensions before decoding while leaving gallery insertion asynchronous.

**Tech Stack:** Flutter/Dart 3.12, `camera` 0.12, Android Camera2 metadata through `MethodChannel`, `record` 7, `image` 4, Flutter widget/unit tests.

## Global Constraints

- Only standalone/openable rear camera IDs may become tappable lens choices.
- The dedicated front/back switch remains; the rear-lens selector never contains a front camera.
- Changing resolution recreates the controller with the same `CameraDescription`.
- Successful photo/video/timeburst completion is silent; background failures remain visible.
- Persist capture mode, rear lens ID, aspect ratio, resolution, flash, and microphone.
- Use the existing JSON preference file and existing state-management style.
- Write a failing test and observe the expected failure before every production behavior change.

---

### Task 1: Serialize and Complete Preference Persistence

**Files:**
- Modify: `lib/services/preferences_service.dart`
- Modify: `lib/screens/camera_screen.dart`
- Modify: `lib/services/camera_service.dart`
- Modify: `lib/services/audio_service.dart`
- Test: `test/preferences_service_test.dart`

**Interfaces:**
- Produces: `PreferencesService.saveSelectedCameraId(String)`, `PreferencesService.loadSelectedCameraId() -> Future<String?>`, and serialized mutation behavior for all existing save methods.
- Consumes: existing `CaptureMode`, `FlashMode`, `ResolutionPreset`, aspect-ratio, and microphone values.

- [ ] **Step 1: Write failing persistence tests**

Add tests that save the six settings concurrently, assert that none overwrite another, and round-trip a selected camera ID:

```dart
test('serializes concurrent setting updates without losing values', () async {
  await Future.wait([
    PreferencesService.saveCaptureMode(CaptureMode.video),
    PreferencesService.saveFlashMode(FlashMode.always),
    PreferencesService.saveResolution(ResolutionPreset.veryHigh),
    PreferencesService.saveAspectRatio(16 / 9),
    PreferencesService.saveSelectedMicrophone('mic-2', 'USB Mic'),
    PreferencesService.saveSelectedCameraId('rear-macro'),
  ]);

  expect(await PreferencesService.loadCaptureMode(), CaptureMode.video);
  expect(await PreferencesService.loadFlashMode(), FlashMode.always);
  expect(await PreferencesService.loadResolution(), ResolutionPreset.veryHigh);
  expect(await PreferencesService.loadAspectRatio(), closeTo(16 / 9, .01));
  expect((await PreferencesService.loadSelectedMicrophone())['id'], 'mic-2');
  expect(await PreferencesService.loadSelectedCameraId(), 'rear-macro');
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/preferences_service_test.dart --plain-name "serializes concurrent setting updates without losing values"`

Expected: FAIL because `saveSelectedCameraId` does not exist and concurrent read/modify/write has no serialization.

- [ ] **Step 3: Implement serialized updates**

Add one queue-backed mutation primitive and route every setting save through it:

```dart
static Future<void> _mutationQueue = Future<void>.value();

static Future<void> _updateAll(
  void Function(Map<String, dynamic> data) mutate,
) {
  final operation = _mutationQueue.then((_) async {
    final data = Map<String, dynamic>.from(await _loadAll());
    mutate(data);
    await _saveAll(data);
  });
  _mutationQueue = operation.catchError((Object _) {});
  return operation;
}

static Future<void> saveSelectedCameraId(String cameraId) =>
    _updateAll((data) => data['selectedCameraId'] = cameraId);

static Future<String?> loadSelectedCameraId() async =>
    (await _loadAll())['selectedCameraId'] as String?;
```

Update `_changeCaptureMode` to await `saveCaptureMode`, make aspect-ratio selection await persistence through `CameraService.setAspectRatio`, and make `AudioService.selectDevice` return `Future<void>` so the UI can await it.

- [ ] **Step 4: Run preference tests and verify GREEN**

Run: `flutter test test/preferences_service_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/preferences_service.dart lib/screens/camera_screen.dart lib/services/camera_service.dart lib/services/audio_service.dart test/preferences_service_test.dart
git commit -m "feat: persist all camera selections reliably"
```

### Task 2: Discover and Classify Accessible Rear Lenses

**Files:**
- Create: `lib/models/camera_lens_info.dart`
- Modify: `android/app/src/main/kotlin/com/example/camerapro/MainActivity.kt`
- Modify: `lib/services/camera_service.dart`
- Test: `test/camera_lens_info_test.dart`
- Test: `test/camera_screen_test.dart`

**Interfaces:**
- Produces: `enum CameraLensKind { ultraWide, wide, telephoto, macro, unknown }`.
- Produces: `CameraLensInfo.fromPlatformMap(Map<Object?, Object?>)` and `CameraLensClassifier.classify(List<CameraLensInfo>)`.
- Produces: `CameraService.backLensInfos`, `CameraService.currentCameraId`, and restored lens initialization.
- Consumes: Android maps with `id`, `lensFacing`, `sensorOrientation`, `focalLengths`, `sensorWidth`, `sensorHeight`, `minimumFocusDistance`, `maxJpegWidth`, `maxJpegHeight`, and `physicalCameraIds`.

- [ ] **Step 1: Write failing classifier tests**

Cover vendor-name detection, equivalent focal-length detection, a macro-like low-resolution auxiliary camera, and ambiguous fallback:

```dart
test('classifies an openable macro-like auxiliary rear camera', () {
  final lenses = CameraLensClassifier.classify([
    lens(id: '0', equivalentMm: 24, pixels: 12 * 1000000),
    lens(
      id: '3',
      equivalentMm: 27,
      pixels: 2 * 1000000,
      minimumFocusDistance: 0,
    ),
  ]);

  expect(lenses.firstWhere((lens) => lens.description.name == '3').kind,
      CameraLensKind.macro);
});
```

- [ ] **Step 2: Run classifier tests and verify RED**

Run: `flutter test test/camera_lens_info_test.dart`

Expected: FAIL because the model and classifier do not exist.

- [ ] **Step 3: Implement the metadata model and deterministic classifier**

Use 35 mm-equivalent focal length when sensor dimensions exist. Prefer explicit vendor names, then classify macro-like auxiliary cameras, then ultra-wide `<20 mm`, telephoto `>50 mm`, wide `20..50 mm`, and unknown otherwise. Return neutral `Kamera N` labels for unknown values.

```dart
enum CameraLensKind { ultraWide, wide, telephoto, macro, unknown }

class CameraLensInfo {
  const CameraLensInfo({
    required this.description,
    required this.kind,
    this.equivalentFocalLength,
    this.minimumFocusDistance,
    this.maxJpegPixels,
    this.physicalCameraIds = const <String>[],
  });

  final CameraDescription description;
  final CameraLensKind kind;
  final double? equivalentFocalLength;
  final double? minimumFocusDistance;
  final int? maxJpegPixels;
  final List<String> physicalCameraIds;
}
```

- [ ] **Step 4: Return native Camera2 metadata for openable IDs**

Extend `getAllPhysicalCameras()` while still iterating `cameraManager.cameraIdList`. Read `LENS_INFO_AVAILABLE_FOCAL_LENGTHS`, `SENSOR_INFO_PHYSICAL_SIZE`, `LENS_INFO_MINIMUM_FOCUS_DISTANCE`, `SCALER_STREAM_CONFIGURATION_MAP` maximum JPEG size, and `physicalCameraIds` on API 28+. Do not append physical-only IDs to the returned list.

- [ ] **Step 5: Integrate lens metadata and saved lens restoration in CameraService**

Load `selectedCameraId` during initialization. Select the matching rear lens or the first rear lens, then persist a new ID only after a successful switch. Preserve the current camera description in `setResolution`:

```dart
Future<void> setResolution(ResolutionPreset preset) async {
  final activeCamera = _controller?.description;
  _resolutionPreset = preset;
  await PreferencesService.saveResolution(preset);
  if (activeCamera != null) {
    await _initCameraController(activeCamera);
  }
}
```

- [ ] **Step 6: Write and run the rear-only selector widget test**

Mock four rear metadata maps and one front map. Assert `Geniş`, `Ultra Geniş`, and `Makro` appear while `Ön Kamera` does not. Recreate the service/screen with a saved rear ID and assert that ID is initialized.

Run: `flutter test test/camera_screen_test.dart --plain-name "lens selector shows only accessible rear lenses"`

Expected before UI integration: FAIL because the screen still consumes raw camera descriptions/positional labels.

- [ ] **Step 7: Commit**

```bash
git add lib/models/camera_lens_info.dart android/app/src/main/kotlin/com/example/camerapro/MainActivity.kt lib/services/camera_service.dart test/camera_lens_info_test.dart test/camera_screen_test.dart
git commit -m "feat: classify and restore accessible rear lenses"
```

### Task 3: Build the Readable Audio Level Panel

**Files:**
- Create: `lib/widgets/audio_level_panel.dart`
- Modify: `lib/screens/camera_screen.dart`
- Test: `test/audio_level_panel_test.dart`

**Interfaces:**
- Produces: `enum AudioLevelBand { low, ideal, high }`.
- Produces: `AudioLevelScale.normalize(double) -> double` and `AudioLevelScale.bandFor(double) -> AudioLevelBand`.
- Produces: `AudioLevelPanel(amplitudes, isRecording, microphoneLabel, onMicrophoneTap)`.

- [ ] **Step 1: Write failing level scale tests**

```dart
test('maps microphone dB values to readable bands', () {
  expect(AudioLevelScale.bandFor(-50), AudioLevelBand.low);
  expect(AudioLevelScale.bandFor(-24), AudioLevelBand.ideal);
  expect(AudioLevelScale.bandFor(-6), AudioLevelBand.high);
  expect(AudioLevelScale.normalize(-60), 0);
  expect(AudioLevelScale.normalize(0), 1);
});
```

- [ ] **Step 2: Run the test and verify RED**

Run: `flutter test test/audio_level_panel_test.dart`

Expected: FAIL because the scale and widget do not exist.

- [ ] **Step 3: Implement the scale, painter, and focused widgets**

Create separate `AudioLevelPanel`, `_MicrophoneButton`, `_WaveformView`, and `_PeakMeter` widget classes. Give the panel key `audio_level_panel`, height `180`, and level text `SES AZ`, `SES İDEAL`, or `SES FAZLA`. Pass theme colors into the painter instead of reading global hardcoded colors.

```dart
static AudioLevelBand bandFor(double db) {
  if (db < -36) return AudioLevelBand.low;
  if (db > -10) return AudioLevelBand.high;
  return AudioLevelBand.ideal;
}
```

- [ ] **Step 4: Write a widget test for layout and level output**

Pump `AudioLevelPanel` with a latest sample of `-8`, assert its height is at least `180`, find `SES FAZLA`, and find key `audio_peak_meter`.

- [ ] **Step 5: Replace the inline screen waveform**

Replace the current `Positioned(height: 140)` row and screen-local `BarWaveformPainter` with `AudioLevelPanel`. Keep the microphone picker callback and disable it while recording.

- [ ] **Step 6: Run tests and verify GREEN**

Run: `flutter test test/audio_level_panel_test.dart test/camera_screen_test.dart`

Expected: PASS after correcting record-channel test mocks to return `{current: -30.0, max: -10.0}` for `getAmplitude`.

- [ ] **Step 7: Commit**

```bash
git add lib/widgets/audio_level_panel.dart lib/screens/camera_screen.dart test/audio_level_panel_test.dart test/camera_screen_test.dart
git commit -m "feat: add readable microphone level panel"
```

### Task 4: Add Shutter Feedback and Silence Successful Saves

**Files:**
- Create: `lib/widgets/capture_flash_overlay.dart`
- Modify: `lib/screens/camera_screen.dart`
- Test: `test/camera_screen_test.dart`

**Interfaces:**
- Produces: `CaptureFlashOverlay(visible: bool)` with key `capture_flash_overlay`.
- Consumes: `_takePicture` raw-capture completion and existing background gallery status updates.

- [ ] **Step 1: Write failing widget tests**

Configure the fake camera to return a temporary JPEG from `takePicture`. Tap the photo button and assert the overlay becomes visible, then fades. Complete background saving and assert no `SnackBar` contains `Fotoğraf kaydedildi`.

```dart
expect(find.byKey(const Key('capture_flash_overlay')), findsOneWidget);
expect(find.text('Fotoğraf kaydedildi'), findsNothing);
```

Add equivalent assertions that video/timeburst success paths do not call a success notification, while an injected gallery error still creates an error snackbar.

- [ ] **Step 2: Run shutter tests and verify RED**

Run: `flutter test test/camera_screen_test.dart --plain-name "photo capture shows shutter feedback without success snackbar"`

Expected: FAIL because there is no overlay and successful processing still calls `_showBackgroundNotification`.

- [ ] **Step 3: Implement the overlay and state transition**

Create a small stateless widget using `IgnorePointer` and `AnimatedOpacity` with theme scrim/black at high opacity. Keep it in the root stack and toggle `_showCaptureFlash` for about 120 milliseconds after a non-null raw capture.

```dart
Future<void> _playCaptureFlash() async {
  if (!mounted) return;
  setState(() => _showCaptureFlash = true);
  await Future<void>.delayed(const Duration(milliseconds: 120));
  if (mounted) setState(() => _showCaptureFlash = false);
}
```

- [ ] **Step 4: Remove success notification calls only**

Keep `_updateGalleryItem` unchanged. Remove `_showBackgroundNotification(..., isError: false)` from photo, video, and timeburst completion. Retain all `isError: true` calls.

- [ ] **Step 5: Run widget tests and verify GREEN**

Run: `flutter test test/camera_screen_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/capture_flash_overlay.dart lib/screens/camera_screen.dart test/camera_screen_test.dart
git commit -m "feat: add shutter feedback and silent save completion"
```

### Task 5: Avoid Unnecessary Full-Resolution JPEG Re-encoding

**Files:**
- Modify: `lib/utils/image_cropper.dart`
- Create: `test/image_cropper_test.dart`

**Interfaces:**
- Produces: `JpegDimensions? readJpegDimensions(Uint8List bytes)`.
- Preserves: `cropImageToAspectRatio(XFile, double) -> Future<XFile?>`.

- [ ] **Step 1: Write failing JPEG parser and crop tests**

Create in-memory JPEGs with the `image` package. Assert the parser returns width/height, a matching ratio leaves file bytes untouched, and a `4:3` image cropped to `1:1` has equal output dimensions.

```dart
final originalBytes = img.encodeJpg(img.Image(width: 400, height: 300));
expect(readJpegDimensions(Uint8List.fromList(originalBytes)),
    const JpegDimensions(width: 400, height: 300));
```

- [ ] **Step 2: Run cropper tests and verify RED**

Run: `flutter test test/image_cropper_test.dart`

Expected: FAIL because `JpegDimensions` and `readJpegDimensions` do not exist.

- [ ] **Step 3: Implement JPEG SOF marker parsing**

Scan marker segments after `FFD8`; for SOF markers `C0,C1,C2,C3,C5,C6,C7,C9,CA,CB,CD,CE,CF`, read big-endian height and width. Validate segment lengths and return `null` for malformed data.

- [ ] **Step 4: Short-circuit matching ratios and lower crop encode cost**

Call `readJpegDimensions` before `img.decodeJpg`. If the aspect delta is below `0.05`, return the original path without decoding. Encode actual crops at quality `92` rather than `100`.

- [ ] **Step 5: Run cropper tests and verify GREEN**

Run: `flutter test test/image_cropper_test.dart`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/utils/image_cropper.dart test/image_cropper_test.dart
git commit -m "perf: skip unnecessary jpeg decoding during capture"
```

### Task 6: Regression Verification and Cleanup

**Files:**
- Modify only files required to correct test harness regressions or analyzer findings.
- Test: `test/camera_screen_test.dart`

**Interfaces:**
- Consumes all prior task interfaces.
- Produces a clean analyzer and complete passing test suite.

- [ ] **Step 1: Fix the existing record mock contract**

Return a map for `getAmplitude` instead of `true`:

```dart
if (method == 'getAmplitude') {
  return <String, double>{'current': -30, 'max': -10};
}
```

- [ ] **Step 2: Correct the existing brightness fade test harness**

Reproduce the test alone, inspect whether the gesture is still active when the fade timer is expected to start, then end the gesture and pump from the timer-start boundary. Do not change production exposure behavior unless a production bug is demonstrated.

Run: `flutter test test/camera_screen_test.dart --plain-name "Should show BrightnessSliderWidget on long press and vertical drag"`

Expected: PASS.

- [ ] **Step 3: Format and analyze**

Run: `dart format lib test android/app/src/main/kotlin/com/example/camerapro/MainActivity.kt`

If Dart formatter rejects Kotlin, format only `lib test` and leave Kotlin manually formatted.

Run: `flutter analyze`

Expected: `No issues found!`.

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`

Expected: all tests pass with no uncaught asynchronous plugin errors.

- [ ] **Step 5: Review the working tree**

Run: `git status --short` and `git diff --check`.

Confirm the user's existing `todo.md` edit and `.superpowers/` visual-companion artifacts are not staged or modified by implementation commits.

- [ ] **Step 6: Commit final test-harness cleanup if needed**

```bash
git add test/camera_screen_test.dart
git commit -m "test: stabilize camera screen plugin mocks"
```
