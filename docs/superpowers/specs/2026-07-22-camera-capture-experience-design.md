# Camera Capture Experience Design

## Goal

Make capture feedback immediate, make microphone level readable, expose every directly accessible rear lens with useful labels, and restore all user-facing camera selections across launches without changing the selected lens unexpectedly.

## Scope

- Keep the front camera out of the rear-lens selector. The existing dedicated front/back switch remains separate.
- Show every directly openable rear camera reported by Android, including wide, ultra-wide, telephoto, and macro when the device exposes them.
- Replace positional lens naming with Android camera metadata classification and a safe generic fallback.
- Increase the waveform panel height and add an at-a-glance low/ideal/high audio level indicator plus a vertical peak meter.
- Show a short black shutter overlay as soon as a photo capture succeeds at the camera boundary.
- Do not show success snackbars after photo, video, or timeburst saving. Keep error snackbars because they require user attention.
- Restore capture mode, rear lens, aspect ratio, resolution, flash mode, and microphone on the next launch.
- Keep the active camera selected while changing resolution.
- Reduce avoidable photo-processing latency while preserving background gallery saving.

## Lens Discovery and Macro Access

Android's `CameraManager.cameraIdList` is the source of cameras that can be opened as standalone devices. Native discovery will attach metadata to each entry: lens facing, orientation, focal lengths, sensor physical size, minimum focus distance, maximum JPEG dimensions, capabilities, and logical-camera physical IDs.

The Flutter layer will retain only openable rear cameras for the lens selector. Lens type classification will use 35 mm-equivalent focal length when the sensor size is available. Ultra-wide and telephoto classifications are relative to the primary rear camera. A low-resolution auxiliary rear camera with close/fixed-focus characteristics may be labeled macro; ambiguous devices receive a neutral `Kamera N` label rather than a false macro label.

Some Android 9+ devices hide auxiliary sensors inside a logical multi-camera. Such physical IDs may be discoverable but cannot be opened directly. They will not be rendered as tappable options because the current Flutter camera backend cannot safely target them. This avoids a selector item that always fails. If a macro sensor is openable, it appears and switches like every other rear lens.

## Camera Selection and Resolution

`CameraService` will own lens metadata and the selected camera ID. At initialization it loads the saved rear camera ID, matches it against the current device's accessible cameras, and falls back to the primary rear camera if the saved device no longer exists.

Changing `ResolutionPreset` requires recreating `CameraController` because media settings are immutable controller construction settings. The service will capture the current `CameraDescription`, persist the new preset, dispose the old controller, and initialize a new controller with the same camera description. Resolution changes therefore reload the preview but do not intentionally change the active lens.

## Audio Level UI

The microphone selector and waveform become a dedicated `AudioLevelPanel` widget instead of a screen helper. The panel is approximately 180 logical pixels high and contains:

- the selected microphone control;
- a taller waveform visualization;
- a status label derived from the latest dB sample;
- a shaded ideal band;
- a vertical peak meter.

Level bands are intentionally simple: below `-36 dB` is low, `-36 dB` through `-10 dB` is ideal, and above `-10 dB` is high. The painter uses the same normalized value as the meter so the two visualizations cannot disagree. The active color changes from the theme primary color to error color while clipping/high input is detected.

## Capture Feedback and Background Processing

Photo capture has two boundaries:

1. `CameraController.takePicture()` completes and a JPEG exists locally.
2. Aspect-ratio processing and gallery insertion complete in the background.

The shutter effect is tied to boundary 1. A black overlay quickly fades in and out over roughly 120 milliseconds while haptic feedback remains. The gallery thumbnail receives a processing item immediately. The capture button is unlocked after the raw JPEG exists, not after gallery insertion.

Successful background completion updates the gallery item silently. Failed processing or saving updates the failed state and keeps an error snackbar. Video and timeburst success notifications are removed by the same rule.

## Photo Latency

The current cropper fully decodes every JPEG before it can determine that no crop is needed, then re-encodes cropped images at quality 100. At maximum resolution these are expensive operations.

The new crop pipeline first reads JPEG dimensions from header markers without decoding pixels. If the captured image already matches the selected aspect ratio within tolerance, it returns the original immediately. Only mismatched images are decoded and cropped in an isolate. Cropped JPEGs use quality 92 to reduce CPU time and file size without a visible mobile-camera quality loss. Gallery insertion remains asynchronous.

Native high-resolution capture time and MediaStore copying cannot be made instantaneous on every device. The design minimizes avoidable Dart work and makes capture acknowledgment immediate even when final gallery processing continues.

## Preference Consistency

The JSON preference file remains the storage mechanism. All preference mutations will pass through one serialized update queue so two rapid settings changes cannot both read an old snapshot and overwrite each other.

Each UI selection awaits or safely schedules its corresponding save:

- capture mode on every mode change;
- selected rear camera ID after a successful lens switch;
- aspect ratio after selection;
- resolution before controller reconstruction;
- flash mode after it is accepted by the service;
- microphone ID and label after selection.

Unavailable saved values fall back safely: photo mode, primary rear camera, `4:3`, maximum resolution, automatic flash, and the first available microphone.

## Error Handling

- Lens discovery failure falls back to Flutter's `availableCameras()` list.
- A saved lens that is absent after a device or OS change falls back to the primary rear camera.
- A lens switch or resolution reinitialization failure leaves the screen in a recoverable non-switching state and reports an error.
- Unsupported flash modes remain caught at the controller boundary.
- Background media errors retain visible error feedback and failed gallery state.
- The waveform renders silence when no microphone samples are available.

## Testing

- Unit-test serialized preference updates and round trips for every remembered choice.
- Unit-test lens classification using representative wide, ultra-wide, telephoto, macro-like, and ambiguous metadata.
- Widget-test that only rear lenses appear in the lens selector and that the saved lens is restored.
- Unit-test dB normalization and low/ideal/high thresholds.
- Widget-test the taller audio panel, level label, and peak meter.
- Widget-test that photo capture triggers the shutter overlay and does not show a success snackbar.
- Unit-test JPEG dimension parsing, no-op crop detection, and cropped output ratio.
- Verify changing resolution reconstructs the controller using the same camera description.

## Out of Scope

- Replacing the Flutter camera plugin with a custom native Camera2 preview/capture stack.
- Forcing direct access to physical-only sensors that Android or the device vendor does not expose as standalone cameras.
- Changing video muxing, recording segmentation, or gallery data architecture beyond notification behavior.
