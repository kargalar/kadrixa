// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.resolution;

import android.annotation.SuppressLint;
import android.annotation.TargetApi;
import android.hardware.camera2.CaptureRequest;
import android.media.CamcorderProfile;
import android.media.EncoderProfiles;
import android.os.Build;
import android.util.Size;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.VisibleForTesting;
import io.flutter.plugins.camera.CameraProperties;
import io.flutter.plugins.camera.SdkCapabilityChecker;
import io.flutter.plugins.camera.features.CameraFeature;
import java.util.List;

/**
 * Controls the resolutions configuration on the {@link android.hardware.camera2} API.
 *
 * <p>The {@link ResolutionFeature} is responsible for converting the platform independent {@link
 * ResolutionPreset} into a {@link android.media.CamcorderProfile} which contains all the properties
 * required to configure the resolution using the {@link android.hardware.camera2} API.
 */
public class ResolutionFeature extends CameraFeature<ResolutionPreset> {
  private static final long MAXIMUM_PREVIEW_PIXELS = 1920L * 1080;
  @Nullable private Size captureSize;
  @Nullable private Size previewSize;
  @Nullable private Size recordingSize;
  private CamcorderProfile recordingProfileLegacy;
  private EncoderProfiles recordingProfile;
  @NonNull private ResolutionPreset currentSetting;
  @NonNull private final CameraProperties cameraProperties;
  private int cameraId;

  /**
   * Creates a new instance of the {@link ResolutionFeature}.
   *
   * @param cameraProperties Collection of characteristics for the current camera device.
   * @param resolutionPreset Platform agnostic enum containing resolution information.
   * @param cameraName Camera identifier of the camera for which to configure the resolution.
   */
  public ResolutionFeature(
      @NonNull CameraProperties cameraProperties,
      @NonNull ResolutionPreset resolutionPreset,
      @NonNull String cameraName) {
    super(cameraProperties);
    this.cameraProperties = cameraProperties;
    this.currentSetting = resolutionPreset;
    try {
      this.cameraId = Integer.parseInt(cameraName, 10);
    } catch (NumberFormatException e) {
      this.cameraId = -1;
      return;
    }
    configureResolution(resolutionPreset, cameraId);
  }

  /**
   * Gets the {@link android.media.CamcorderProfile} containing the information to configure the
   * resolution using the {@link android.hardware.camera2} API.
   *
   * @return Resolution information to configure the {@link android.hardware.camera2} API.
   */
  @Nullable
  public CamcorderProfile getRecordingProfileLegacy() {
    return this.recordingProfileLegacy;
  }

  @Nullable
  public EncoderProfiles getRecordingProfile() {
    return this.recordingProfile;
  }

  /**
   * Gets the optimal preview size based on the configured resolution.
   *
   * @return The optimal preview size.
   */
  @Nullable
  public Size getPreviewSize() {
    return this.previewSize;
  }

  /**
   * Gets the optimal capture size based on the configured resolution.
   *
   * @return The optimal capture size.
   */
  @Nullable
  public Size getCaptureSize() {
    return this.captureSize;
  }

  @Nullable
  public Size getRecordingSize() {
    return recordingSize;
  }

  /** Updates encoder output without recreating the photo reader or preview surface. */
  public void setRecordingResolution(@NonNull ResolutionPreset preset) {
    Size photoSize = captureSize;
    Size previousPreviewSize = previewSize;
    configureResolution(preset, cameraId);
    captureSize = photoSize;
    previewSize = previousPreviewSize;
  }

  @NonNull
  @Override
  public String getDebugName() {
    return "ResolutionFeature";
  }

  @SuppressLint("KotlinPropertyAccess")
  @NonNull
  @Override
  public ResolutionPreset getValue() {
    return currentSetting;
  }

  @Override
  public void setValue(@NonNull ResolutionPreset value) {
    this.currentSetting = value;
    configureResolution(currentSetting, cameraId);
  }

  @Override
  public final boolean checkIsSupported() {
    return cameraId >= 0;
  }

  @Override
  public void updateBuilder(@NonNull CaptureRequest.Builder requestBuilder) {
    // No-op: when setting a resolution there is no need to update the request builder.
  }

  @VisibleForTesting
  static Size computeBestPreviewSize(int cameraId, ResolutionPreset preset)
      throws IndexOutOfBoundsException {
    if (preset.ordinal() > ResolutionPreset.high.ordinal()) {
      preset = ResolutionPreset.high;
    }
    if (SdkCapabilityChecker.supportsEncoderProfiles()) {
      EncoderProfiles profile =
          getBestAvailableCamcorderProfileForResolutionPreset(cameraId, preset);
      List<EncoderProfiles.VideoProfile> videoProfiles = profile.getVideoProfiles();
      EncoderProfiles.VideoProfile defaultVideoProfile = videoProfiles.get(0);

      if (defaultVideoProfile != null) {
        return new Size(defaultVideoProfile.getWidth(), defaultVideoProfile.getHeight());
      }
    }

    // TODO(camsim99): Suppression is currently safe because legacy code is used as a fallback for
    // SDK < S.
    // This should be removed when reverting that fallback behavior:
    // https://github.com/flutter/flutter/issues/119668.
    CamcorderProfile profile =
        getBestAvailableCamcorderProfileForResolutionPresetLegacy(cameraId, preset);
    return new Size(profile.videoFrameWidth, profile.videoFrameHeight);
  }

  /**
   * Gets the best possible {@link android.media.CamcorderProfile} for the supplied {@link
   * ResolutionPreset}. Supports SDK < 31.
   *
   * @param cameraId Camera identifier which indicates the device's camera for which to select a
   *     {@link android.media.CamcorderProfile}.
   * @param preset The {@link ResolutionPreset} for which is to be translated to a {@link
   *     android.media.CamcorderProfile}.
   * @return The best possible {@link android.media.CamcorderProfile} that matches the supplied
   *     {@link ResolutionPreset}.
   */
  @SuppressLint("UseRequiresApi")
  @TargetApi(Build.VERSION_CODES.R)
  // All of these cases deliberately fall through to get the best available profile.
  @SuppressWarnings({"fallthrough", "deprecation"})
  @NonNull
  public static CamcorderProfile getBestAvailableCamcorderProfileForResolutionPresetLegacy(
      int cameraId, @NonNull ResolutionPreset preset) {
    if (cameraId < 0) {
      throw new AssertionError(
          "getBestAvailableCamcorderProfileForResolutionPreset can only be used with valid (>=0)"
              + " camera identifiers.");
    }

    switch (preset) {
      case max:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_HIGH)) {
          return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_HIGH);
        }
      // fall through
      case ultraHigh:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_2160P)) {
          return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_2160P);
        }
      // fall through
      case veryHigh:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_1080P)) {
          return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_1080P);
        }
      // fall through
      case high:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_720P)) {
          return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_720P);
        }
      // fall through
      case medium:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_480P)) {
          return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_480P);
        }
      // fall through
      case low:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_QVGA)) {
          return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_QVGA);
        }
      // fall through
      default:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_LOW)) {
          return CamcorderProfile.get(cameraId, CamcorderProfile.QUALITY_LOW);
        } else {
          throw new IllegalArgumentException(
              "No capture session available for current capture session.");
        }
    }
  }

  @SuppressLint("UseRequiresApi")
  @TargetApi(Build.VERSION_CODES.S)
  // All of these cases deliberately fall through to get the best available profile.
  @SuppressWarnings("fallthrough")
  @NonNull
  public static EncoderProfiles getBestAvailableCamcorderProfileForResolutionPreset(
      int cameraId, @NonNull ResolutionPreset preset) {
    if (cameraId < 0) {
      throw new AssertionError(
          "getBestAvailableCamcorderProfileForResolutionPreset can only be used with valid (>=0)"
              + " camera identifiers.");
    }

    String cameraIdString = Integer.toString(cameraId);

    switch (preset) {
      case max:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_HIGH)) {
          return CamcorderProfile.getAll(cameraIdString, CamcorderProfile.QUALITY_HIGH);
        }
      // fall through
      case ultraHigh:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_2160P)) {
          return CamcorderProfile.getAll(cameraIdString, CamcorderProfile.QUALITY_2160P);
        }
      // fall through
      case veryHigh:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_1080P)) {
          return CamcorderProfile.getAll(cameraIdString, CamcorderProfile.QUALITY_1080P);
        }
      // fall through
      case high:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_720P)) {
          return CamcorderProfile.getAll(cameraIdString, CamcorderProfile.QUALITY_720P);
        }
      // fall through
      case medium:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_480P)) {
          return CamcorderProfile.getAll(cameraIdString, CamcorderProfile.QUALITY_480P);
        }
      // fall through
      case low:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_QVGA)) {
          return CamcorderProfile.getAll(cameraIdString, CamcorderProfile.QUALITY_QVGA);
        }
      // fall through
      default:
        if (CamcorderProfile.hasProfile(cameraId, CamcorderProfile.QUALITY_LOW)) {
          return CamcorderProfile.getAll(cameraIdString, CamcorderProfile.QUALITY_LOW);
        }

        throw new IllegalArgumentException(
            "No capture session available for current capture session.");
    }
  }

  private void configureResolution(ResolutionPreset resolutionPreset, int cameraId)
      throws IndexOutOfBoundsException {
    if (!checkIsSupported()) {
      return;
    }
    int profileCameraId = cameraId;
    try {
      configureRecordingProfile(resolutionPreset, profileCameraId);
    } catch (IllegalArgumentException error) {
      // Auxiliary and physical lenses often have no dedicated camcorder profile.
      // Reuse encoder settings from the primary camera, then constrain its output size.
      if (cameraId == 0) {
        throw error;
      }
      profileCameraId = 0;
      configureRecordingProfile(resolutionPreset, profileCameraId);
    }
    recordingSize = captureSize;
    // The preview uses the same stream ratio and sensor crop as the recorder.
    // A smaller preview buffer avoids unsupported dual-4K output combinations.
    Size[] videoSizes = videoSizesWithMatchingPreview();
    double ratio = PhotoAspectRatioStore.getTargetAspectRatio();
    int shortEdge = recordingShortEdge(resolutionPreset);
    Size supportedRecordingSize = shortEdge == 0
        ? AspectRatioSizeSelector.selectForCrop(videoSizes, ratio, pixelCount(recordingSize))
        : AspectRatioSizeSelector.selectForVideo(videoSizes, ratio, shortEdge);
    if (supportedRecordingSize != null) {
      recordingSize = supportedRecordingSize;
    }
    previewSize = recordingSize;
    Size matchingPreview = AspectRatioSizeSelector.select(
        cameraProperties.getAvailablePreviewSizes(),
        (double) recordingSize.getWidth() / recordingSize.getHeight(),
        Math.min(pixelCount(recordingSize), MAXIMUM_PREVIEW_PIXELS));
    if (matchingPreview != null) previewSize = matchingPreview;
    if (!PhotoAspectRatioStore.isVideoPreviewEnabled()) {
      previewSize = computeBestPreviewSize(profileCameraId, resolutionPreset);
    }
    applyTargetAspectRatio();
  }

  private static int recordingShortEdge(ResolutionPreset preset) {
    switch (preset) {
      case low: return 240;
      case medium: return 480;
      case high: return 720;
      case veryHigh: return 1080;
      case ultraHigh: return 2160;
      default: return 0;
    }
  }

  private Size[] videoSizesWithMatchingPreview() {
    Size[] videoSizes = cameraProperties.getAvailableVideoSizes();
    Size[] previewSizes = cameraProperties.getAvailablePreviewSizes();
    if (videoSizes == null || previewSizes == null) return null;
    java.util.ArrayList<Size> common = new java.util.ArrayList<>();
    for (Size video : videoSizes) {
      for (Size preview : previewSizes) {
        double videoRatio = (double) video.getWidth() / video.getHeight();
        double previewRatio = (double) preview.getWidth() / preview.getHeight();
        if (Math.abs(videoRatio - previewRatio) < 0.001) { common.add(video); break; }
      }
    }
    return common.toArray(new Size[0]);
  }

  private void configureRecordingProfile(ResolutionPreset resolutionPreset, int cameraId) {
    boolean captureSizeCalculated = false;

    if (SdkCapabilityChecker.supportsEncoderProfiles()) {
      recordingProfileLegacy = null;
      recordingProfile =
          getBestAvailableCamcorderProfileForResolutionPreset(cameraId, resolutionPreset);
      List<EncoderProfiles.VideoProfile> videoProfiles = recordingProfile.getVideoProfiles();

      EncoderProfiles.VideoProfile defaultVideoProfile = videoProfiles.get(0);

      if (defaultVideoProfile != null) {
        captureSizeCalculated = true;
        captureSize = new Size(defaultVideoProfile.getWidth(), defaultVideoProfile.getHeight());
      }
    }

    if (!captureSizeCalculated) {
      recordingProfile = null;
      CamcorderProfile camcorderProfile =
          getBestAvailableCamcorderProfileForResolutionPresetLegacy(cameraId, resolutionPreset);
      recordingProfileLegacy = camcorderProfile;
      captureSize =
          new Size(recordingProfileLegacy.videoFrameWidth, recordingProfileLegacy.videoFrameHeight);
    }

  }

  private void applyTargetAspectRatio() {
    if (captureSize == null || previewSize == null) {
      return;
    }

    final double targetAspectRatio = PhotoAspectRatioStore.getTargetAspectRatio();
    // Still image quality is independent from camcorder profiles and video presets.
    final long capturePixelBudget = Long.MAX_VALUE;
    if (!PhotoAspectRatioStore.isVideoPreviewEnabled()) {
      Size selectedPreviewSize = AspectRatioSizeSelector.selectForCrop(
          cameraProperties.getAvailablePreviewSizes(), targetAspectRatio, pixelCount(previewSize));
      if (selectedPreviewSize != null) previewSize = selectedPreviewSize;
    }
    final Size selectedCaptureSize =
        AspectRatioSizeSelector.selectForCrop(
            cameraProperties.getAvailableJpegSizes(), targetAspectRatio, capturePixelBudget);

    if (selectedCaptureSize != null) {
      captureSize = selectedCaptureSize;
    }
  }

  private static long pixelCount(@NonNull Size size) {
    return (long) size.getWidth() * size.getHeight();
  }
}
