import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants/app_brand.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/camera_screen.dart';
import 'services/background_media_processing_service.dart';
import 'theme/app_theme.dart';
import 'services/camera_intent_service.dart';

import 'package:camera_android/camera_android.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("=== MAIN: WidgetsBinding initialized ===");

  AndroidCamera.registerWith();
  debugPrint("=== MAIN: AndroidCamera registered ===");

  await BackgroundMediaProcessingService.initialize();
  debugPrint("=== MAIN: Background media processing initialized ===");

  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  debugPrint("=== MAIN: Orientation set ===");

  await [
    Permission.camera,
    Permission.microphone,
    Permission.storage,
    Permission.photos,
    Permission.videos,
  ].request();
  debugPrint("=== MAIN: Permissions requested ===");

  final launchRequest = await CameraIntentService.loadRequest();
  runApp(KadrixaApp(launchRequest: launchRequest));
  debugPrint("=== MAIN: runApp called ===");
}

class KadrixaApp extends StatelessWidget {
  const KadrixaApp({super.key, this.launchRequest});
  final CameraLaunchRequest? launchRequest;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: CameraScreen(launchRequest: launchRequest),
    );
  }
}
