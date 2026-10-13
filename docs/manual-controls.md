# Compact camera controls and manual focus

The camera switch action sits to the right of the centered shutter button in
photo and video modes, including active video recordings. It uses the existing
recording-safe lens-switch flow. Switching is disabled while the camera is
changing state and while a timeburst is recording.

Manual settings use a 128 dp panel with ISO, shutter, and focus selectors. One
slider edits the selected parameter. The viewfinder reserves space for the
panel in portrait and landscape, preserving the visible capture frame.

The Android camera catalog reports manual focus support and the lens's maximum
focus distance. Unsupported lenses expose a disabled focus slider with an
explanation. The focus control spans infinity to the actual lens limit and
displays estimated subject distance instead of an arbitrary percentage.

Manual focus is part of the camera plugin's autofocus feature, rather than a
temporary mutation of the preview request. It sets AF off, resets AF trigger
to idle, and applies lens focus distance together. Builder updates and still
captures preserve these values; a still capture skips the autofocus sequence.
Feature recreation for recording retains manual focus. Controller recreation
reapplies the selected distance within the new lens's bounds. Auto reset removes
manual focus and restores the appropriate picture or video autofocus mode.

The method channel reports native failures instead of silently accepting them.
Widget tests verify the compact panel, unobscured preview, unsupported lenses,
actual focus range sent to Android, auto reset, and switch button placement.
Native tests verify clamping, invalid inputs, preview/still request application,
autofocus stability, and restoration of automatic focus.

The request behavior follows [Android's focus-distance and autofocus controls](https://developer.android.com/reference/android/hardware/camera2/CaptureRequest).
