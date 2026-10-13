# Photo preview and saved orientation

Front-camera photos preserve the mirrored appearance of the viewfinder. The
capture screen snapshots the active lens before capture and persists
`mirrorHorizontally` in the background photo job. Camera-intent photos and
timeburst stills use the same processing option. Rear-camera captures retain
their original reflection behavior.

Android crops the encoded JPEG region, applies the EXIF rotation, and mirrors
the displayed horizontal axis before encoding. The saved pixels have normal
EXIF orientation, so the app gallery and device gallery receive the same image.
The Dart fallback applies the equivalent transformation outside the UI isolate.
JPEGs that already describe a reflection in EXIF do not receive an additional
reflection.

The processed JPEG carries `Software=Kadrixa:preview-mirrored:v1`. This marker
is written with the transformed pixels before atomic replacement, so a worker
retry cannot reverse the photo again. Cropping preserves the marker. Old queued
jobs without `mirrorHorizontally` retain their previous behavior.

Capture animations and gallery thumbnails display the processed photo rather
than caching an unprocessed image under the final filename.

Regression checks use four differently colored quadrants to verify all eight
EXIF orientations, square cropping, and byte-for-byte stability after retry.
Android instrumentation additionally checks that MediaStore receives the same
JPEG bytes and that rear-camera captures retain their original bytes.

Orientation references: [Android EXIF constants](https://developer.android.com/reference/android/media/ExifInterface)
and [image orientation transforms](https://pub.dev/documentation/image/latest/image/bakeOrientation.html).
