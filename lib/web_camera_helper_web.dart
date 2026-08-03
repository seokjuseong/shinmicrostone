import 'dart:html' as html;
import 'package:camera/camera.dart';


Future<List<CameraDescription>> safeAvailableCameras() async {

  try {
    return await availableCameras();

  } catch (e) {

    print("camera plugin failed: $e");


    final devices =
    await html.window.navigator.mediaDevices!.enumerateDevices();


    final cameras = devices
        .where((d) => d.kind == 'videoinput')
        .map((d) {

      return CameraDescription(
        name: d.label.isNotEmpty
            ? d.label
            : "Web Camera ${d.deviceId}",

        lensDirection:
        CameraLensDirection.front,

        sensorOrientation: 0,
      );

    })
        .toList();


    return cameras;
  }
}