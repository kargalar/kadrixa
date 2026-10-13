package io.flutter.plugins.camera;

import androidx.annotation.Nullable;
import java.util.HashMap;
import java.util.Map;

/** Maps non-public physical lenses to the public logical camera that owns them. */
public final class PhysicalCameraRegistry {
  private static final Map<String, String> logicalCameraIds = new HashMap<>();

  private PhysicalCameraRegistry() {}

  public static synchronized void clear() {
    logicalCameraIds.clear();
  }

  public static synchronized void register(String physicalId, String logicalId) {
    logicalCameraIds.putIfAbsent(physicalId, logicalId);
  }

  @Nullable
  static synchronized String getLogicalCameraId(String physicalId) {
    return logicalCameraIds.get(physicalId);
  }
}
