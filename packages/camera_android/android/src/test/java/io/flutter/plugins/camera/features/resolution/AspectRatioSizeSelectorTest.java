// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camera.features.resolution;

import static org.junit.Assert.assertEquals;

import android.util.Size;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

@RunWith(RobolectricTestRunner.class)
public class AspectRatioSizeSelectorTest {
  @Test
  public void videoSizeRetainsRequestedResolutionAfterCropping() {
    Size[] sizes = {new Size(320, 240), new Size(640, 480), new Size(1024, 768), new Size(1280, 720), new Size(1920, 1080)};
    assertEquals(new Size(1280, 720), AspectRatioSizeSelector.selectForVideo(sizes, 16.0 / 9.0, 720));
    assertEquals(new Size(1024, 768), AspectRatioSizeSelector.selectForVideo(sizes, 4.0 / 3.0, 720));
    assertEquals(new Size(1024, 768), AspectRatioSizeSelector.selectForVideo(sizes, 1.0, 720));
    assertEquals(new Size(640, 480), AspectRatioSizeSelector.selectForVideo(sizes, 16.0 / 9.0, 240));
  }
  @Test
  public void squarePhotoUsesFullResolutionInsteadOfThumbnailSize() {
    final Size[] sizes = {new Size(288, 288), new Size(4000, 3000), new Size(3840, 2160)};
    assertEquals(new Size(4000, 3000), AspectRatioSizeSelector.selectForCrop(sizes, 1.0, Long.MAX_VALUE));
  }

  @Test
  public void widePhotoMaximizesPixelsRemainingAfterCrop() {
    final Size[] sizes = {new Size(4000, 3000), new Size(3840, 2160)};
    assertEquals(new Size(4000, 3000), AspectRatioSizeSelector.selectForCrop(sizes, 16.0 / 9.0, Long.MAX_VALUE));
  }

  @Test
  public void previewCropStaysWithinThePreviewPixelBudget() {
    final Size[] sizes = {new Size(288, 288), new Size(4000, 3000), new Size(1024, 768), new Size(1280, 720)};
    assertEquals(new Size(1024, 768), AspectRatioSizeSelector.selectForCrop(sizes, 1.0, 1280L * 720));
  }

  @Test
  public void selectsLargestFourByThreeSizeWithinPixelBudget() {
    final Size[] sizes = {
      new Size(3840, 2160),
      new Size(3264, 2448),
      new Size(1920, 1080),
      new Size(1600, 1200)
    };

    final Size selected =
        AspectRatioSizeSelector.select(sizes, 4.0 / 3.0, 3840L * 2160L);

    assertEquals(new Size(3264, 2448), selected);
  }

  @Test
  public void selectsLargestSixteenByNineSizeWithinPixelBudget() {
    final Size[] sizes = {
      new Size(4000, 3000), new Size(3840, 2160), new Size(1920, 1080)
    };

    final Size selected =
        AspectRatioSizeSelector.select(sizes, 16.0 / 9.0, 3840L * 2160L);

    assertEquals(new Size(3840, 2160), selected);
  }

  @Test
  public void usesClosestAvailableRatioWhenSquareOutputIsUnavailable() {
    final Size[] sizes = {new Size(1920, 1080), new Size(1440, 1080)};

    final Size selected = AspectRatioSizeSelector.select(sizes, 1.0, Long.MAX_VALUE);

    assertEquals(new Size(1440, 1080), selected);
  }
}
