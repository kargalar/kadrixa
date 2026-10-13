// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.resolution;

import android.util.Size;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

/** Selects the largest camera output size matching a target aspect ratio and pixel budget. */
final class AspectRatioSizeSelector {
  private static final double RATIO_TOLERANCE = 0.025;

  private AspectRatioSizeSelector() {}

  /** Smallest stream that retains the requested short edge after a center crop. */
  @Nullable
  static Size selectForVideo(@Nullable Size[] sizes, double targetAspectRatio, int shortEdge) {
    if (sizes == null) return null;
    Size sufficient = null;
    Size fallback = null;
    double largestRetainedEdge = 0;
    for (Size size : sizes) {
      double width = Math.max(size.getWidth(), size.getHeight());
      double height = Math.min(size.getWidth(), size.getHeight());
      double cropWidth = Math.min(width, height * targetAspectRatio);
      double cropHeight = Math.min(height, width / targetAspectRatio);
      double retainedEdge = Math.min(cropWidth, cropHeight);
      if (retainedEdge >= shortEdge) {
        if (sufficient == null || pixelCount(size) < pixelCount(sufficient)) sufficient = size;
      } else if (retainedEdge > largestRetainedEdge) {
        fallback = size;
        largestRetainedEdge = retainedEdge;
      }
    }
    return sufficient != null ? sufficient : fallback;
  }

  /** Maximizes usable pixels after cropping, avoiding tiny square thumbnail outputs. */
  @Nullable
  static Size selectForCrop(@Nullable Size[] sizes, double targetAspectRatio, long maximumPixels) {
    if (sizes == null) return null;
    Size best = null;
    long bestRetainedPixels = 0;
    long bestSourcePixels = Long.MAX_VALUE;
    for (Size size : sizes) {
      final long sourcePixels = pixelCount(size);
      if (sourcePixels <= 0 || sourcePixels > maximumPixels) continue;
      final int width = Math.max(size.getWidth(), size.getHeight());
      final int height = Math.min(size.getWidth(), size.getHeight());
      final long cropWidth = Math.min(width, Math.round(height * targetAspectRatio));
      final long cropHeight = Math.min(height, Math.round(width / targetAspectRatio));
      final long retainedPixels = cropWidth * cropHeight;
      if (retainedPixels > bestRetainedPixels
          || (retainedPixels == bestRetainedPixels && sourcePixels < bestSourcePixels)) {
        best = size;
        bestRetainedPixels = retainedPixels;
        bestSourcePixels = sourcePixels;
      }
    }
    return best;
  }

  @Nullable
  static Size select(
      @Nullable Size[] sizes, double targetAspectRatio, long maximumPixels) {
    if (sizes == null || sizes.length == 0) {
      return null;
    }

    Size bestMatching = null;
    Size bestFallback = null;
    double bestFallbackDifference = Double.MAX_VALUE;

    for (Size size : sizes) {
      final long pixels = (long) size.getWidth() * size.getHeight();
      if (pixels <= 0 || pixels > maximumPixels) {
        continue;
      }

      final double ratio = (double) Math.max(size.getWidth(), size.getHeight())
          / Math.min(size.getWidth(), size.getHeight());
      final double difference = Math.abs(ratio - targetAspectRatio);

      if (difference <= RATIO_TOLERANCE) {
        if (bestMatching == null || pixels > pixelCount(bestMatching)) {
          bestMatching = size;
        }
      } else if (bestFallback == null
          || difference < bestFallbackDifference
          || (Math.abs(difference - bestFallbackDifference) < 0.0001
              && pixels > pixelCount(bestFallback))) {
        bestFallback = size;
        bestFallbackDifference = difference;
      }
    }

    return bestMatching != null ? bestMatching : bestFallback;
  }

  private static long pixelCount(@NonNull Size size) {
    return (long) size.getWidth() * size.getHeight();
  }
}
