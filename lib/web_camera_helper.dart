import 'package:camera/camera.dart';

Future<List<CameraDescription>> safeAvailableCameras() async {
  return await availableCameras();
}