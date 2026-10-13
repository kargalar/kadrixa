package io.flutter.plugins.camera;

import android.hardware.camera2.CaptureRequest;
import android.media.AudioDeviceInfo;
import android.os.Build;
import android.util.Log;
import io.flutter.plugin.common.MethodChannel;

public class CameraAccessor {
  @SuppressWarnings("unchecked")
  public static void setCaptureRequestOption(
      CameraPlugin plugin, CaptureRequest.Key key, Object value) {
    if (plugin == null) return;
    try {
      java.lang.reflect.Field apiField = CameraPlugin.class.getDeclaredField("cameraApi");
      apiField.setAccessible(true);
      CameraApiImpl api = (CameraApiImpl) apiField.get(plugin);
      if (api == null || api.camera == null) return;

      Camera camera = api.camera;
      if (camera.previewRequestBuilder != null) {
        camera.previewRequestBuilder.set(key, value);
        camera.refreshPreviewCaptureSession(
            null,
            new ErrorCallback() {
              @Override
              public void onError(String errorCode, String errorMessage) {
                Log.e(
                    "CameraAccessor",
                    "Error refreshing preview: " + errorCode + ", " + errorMessage);
              }
            });
      }
    } catch (Exception e) {
      Log.e("CameraAccessor", "Failed to set capture request option", e);
    }
  }

  public static void setPreferredAudioDeviceId(CameraPlugin plugin, String deviceId) {
    Camera camera = getActiveCamera(plugin);
    if (camera == null) throw new IllegalStateException("Camera is not initialized.");
    camera.setPreferredAudioDeviceId(deviceId);
  }

  public static void setManualFocusDistance(
      CameraPlugin plugin, Float distance, MethodChannel.Result result) {
    Camera camera = getActiveCamera(plugin);
    if (camera == null) throw new IllegalStateException("Camera is not initialized.");
    camera.setManualFocusDistance(
        distance, () -> result.success(null), (code, message) -> result.error(code, message, null));
  }

  public static void configureVideoRecording(
      CameraPlugin plugin, String preset, boolean allowStillCapture) {
    Camera camera = getActiveCamera(plugin);
    if (camera == null) throw new IllegalStateException("Camera is not initialized.");
    camera.configureVideoRecording(preset, allowStillCapture);
  }

  public static String getRoutedAudioDeviceId(CameraPlugin plugin) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return "unsupported";
    Camera camera = getActiveCamera(plugin);
    if (camera == null || camera.mediaRecorder == null) return "-1";
    AudioDeviceInfo device = camera.mediaRecorder.getRoutedDevice();
    return device == null ? "-1" : Integer.toString(device.getId());
  }

  public static double getRecordingAmplitudeDb(CameraPlugin plugin) {
    Camera camera = getActiveCamera(plugin);
    if (camera == null || camera.mediaRecorder == null) return -50.0;
    int amplitude = camera.mediaRecorder.getMaxAmplitude();
    if (amplitude <= 0) return -50.0;
    return 20.0 * Math.log10(amplitude / 32767.0);
  }

  public static boolean isVideoRecordingStarted(CameraPlugin plugin) {
    Camera camera = getActiveCamera(plugin);
    return camera != null && camera.isVideoRecordingStarted();
  }

  private static Camera getActiveCamera(CameraPlugin plugin) {
    if (plugin == null) return null;
    try {
      java.lang.reflect.Field apiField = CameraPlugin.class.getDeclaredField("cameraApi");
      apiField.setAccessible(true);
      CameraApiImpl api = (CameraApiImpl) apiField.get(plugin);
      return api == null ? null : api.camera;
    } catch (Exception e) {
      Log.e("CameraAccessor", "Failed to access active camera", e);
      return null;
    }
  }
}
