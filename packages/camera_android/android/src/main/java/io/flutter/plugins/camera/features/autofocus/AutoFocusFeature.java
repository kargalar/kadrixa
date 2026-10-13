// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.autofocus;

import android.annotation.SuppressLint;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CaptureRequest;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.plugins.camera.CameraProperties;
import io.flutter.plugins.camera.features.CameraFeature;

/** Controls the auto focus configuration on the {@see anddroid.hardware.camera2} API. */
public class AutoFocusFeature extends CameraFeature<FocusMode> {
  @NonNull private FocusMode currentSetting = FocusMode.auto;
  @Nullable private Float manualFocusDistance;

  // When switching recording modes this feature is re-created with the appropriate setting here.
  private final boolean recordingVideo;

  /**
   * Creates a new instance of the {@see AutoFocusFeature}.
   *
   * @param cameraProperties Collection of the characteristics for the current camera device.
   * @param recordingVideo Indicates whether the camera is currently recording video.
   */
  public AutoFocusFeature(@NonNull CameraProperties cameraProperties, boolean recordingVideo) {
    super(cameraProperties);
    this.recordingVideo = recordingVideo;
  }

  @NonNull
  @Override
  public String getDebugName() {
    return "AutoFocusFeature";
  }

  @NonNull
  @SuppressLint("KotlinPropertyAccess")
  @Override
  public FocusMode getValue() {
    return currentSetting;
  }

  @Override
  public void setValue(@NonNull FocusMode value) {
    this.currentSetting = value;
  }

  @Nullable
  public Float getManualFocusDistance() {
    return manualFocusDistance;
  }

  public boolean isManualFocusEnabled() {
    return manualFocusDistance != null;
  }

  public boolean isManualFocusSupported() {
    Float limit = cameraProperties.getLensInfoMinimumFocusDistance();
    int[] modes = cameraProperties.getControlAutoFocusAvailableModes();
    if (limit == null || !Float.isFinite(limit) || limit <= 0 || modes == null) return false;
    for (int mode : modes) {
      if (mode == CaptureRequest.CONTROL_AF_MODE_OFF) return true;
    }
    return false;
  }

  public void setManualFocusDistance(@Nullable Float distance) {
    if (distance == null) {
      manualFocusDistance = null;
      currentSetting = FocusMode.auto;
      return;
    }
    if (!Float.isFinite(distance))
      throw new IllegalArgumentException("Focus distance must be finite.");
    if (!isManualFocusSupported())
      throw new UnsupportedOperationException("This lens has no manual focus.");
    manualFocusDistance =
        Math.max(0f, Math.min(distance, cameraProperties.getLensInfoMinimumFocusDistance()));
  }

  @Override
  public boolean checkIsSupported() {
    int[] modes = cameraProperties.getControlAutoFocusAvailableModes();

    final Float minFocus = cameraProperties.getLensInfoMinimumFocusDistance();

    // Check if the focal length of the lens is fixed. If the minimum focus distance == 0, then the
    // focal length  is fixed. The minimum focus distance can be null on some devices:
    // https://developer.android.com/reference/android/hardware/camera2/CameraCharacteristics#LENS_INFO_MINIMUM_FOCUS_DISTANCE
    boolean isFixedLength = minFocus == null || minFocus == 0;

    return !isFixedLength
        && !(modes.length == 0
            || (modes.length == 1 && modes[0] == CameraCharacteristics.CONTROL_AF_MODE_OFF));
  }

  @Override
  public void updateBuilder(@NonNull CaptureRequest.Builder requestBuilder) {
    if (manualFocusDistance != null) {
      requestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_OFF);
      requestBuilder.set(CaptureRequest.CONTROL_AF_TRIGGER, CaptureRequest.CONTROL_AF_TRIGGER_IDLE);
      requestBuilder.set(CaptureRequest.LENS_FOCUS_DISTANCE, manualFocusDistance);
      return;
    }
    if (!checkIsSupported()) {
      return;
    }

    switch (currentSetting) {
      case locked:
        // When locking the auto-focus the camera device should do a one-time focus and afterwards
        // set the auto-focus to idle. This is accomplished by setting the CONTROL_AF_MODE to
        // CONTROL_AF_MODE_AUTO.
        requestBuilder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_AUTO);
        break;
      case auto:
        requestBuilder.set(
            CaptureRequest.CONTROL_AF_MODE,
            recordingVideo
                ? CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO
                : CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
        break;
      default:
        break;
    }
  }
}
