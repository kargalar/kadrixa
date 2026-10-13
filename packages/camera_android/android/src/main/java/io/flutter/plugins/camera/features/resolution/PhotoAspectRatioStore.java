// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.resolution;

/** Holds the still-photo aspect ratio requested before a camera controller is created. */
public final class PhotoAspectRatioStore {
  private static volatile double targetAspectRatio = 4.0 / 3.0;
  private static volatile boolean videoPreviewEnabled;

  private PhotoAspectRatioStore() {}

  public static double getTargetAspectRatio() {
    return targetAspectRatio;
  }

  public static boolean isVideoPreviewEnabled() { return videoPreviewEnabled; }

  public static void setVideoPreviewEnabled(boolean enabled) { videoPreviewEnabled = enabled; }

  public static void setTargetAspectRatio(double ratio) {
    if (Double.isFinite(ratio) && ratio > 0.0) {
      targetAspectRatio = ratio;
    }
  }
}
