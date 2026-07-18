import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medication Tracker',
      theme: ThemeData.dark(),
      home: MedicationScreen(cameras: cameras),
    );
  }
}

class MedicationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MedicationScreen({super.key, required this.cameras});

  @override
  State<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends State<MedicationScreen> {
  CameraController? _cameraController;
  PoseDetector?     _poseDetector;
  OrtSession?       _ortSession;

  bool   _isDetecting = false;
  bool   _isIntake    = false;
  double _probability = 0.0;
  int    _eventCount  = 0;
  int    _consecutive = 0;
  bool   _prevIntake  = false;

  double _prevRWX = 0, _prevRWY = 0, _prevRWZ = 0;
  double _prevLWX = 0, _prevLWY = 0, _prevLWZ = 0;

  static const int minConsecutive = 5;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await Permission.camera.request();

    // ONNX
    OrtEnv.instance.init();
    final data  = await rootBundle.load('assets/medication_model.onnx');
    final bytes = data.buffer.asUint8List();
    _ortSession = OrtSession.fromBuffer(bytes, OrtSessionOptions());

    // MediaPipe Pose
    _poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.accurate,
        mode:  PoseDetectionMode.stream,
      ),
    );

    // Front camera
    final front = widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    _cameraController = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21,
    );
    await _cameraController!.initialize();
    _cameraController!.startImageStream(_onFrame);
    setState(() {});
  }

  void _onFrame(CameraImage image) async {
    if (_isDetecting) return;
    _isDetecting = true;
    try {
      final inputImage = _toInputImage(image);
      if (inputImage == null) { _isDetecting = false; return; }

      final poses = await _poseDetector!.processImage(inputImage);
      if (poses.isEmpty)      { _isDetecting = false; return; }

      final lm = poses.first.landmarks;

      final nose      = lm[PoseLandmarkType.nose];
      final rWrist    = lm[PoseLandmarkType.rightWrist];
      final lWrist    = lm[PoseLandmarkType.leftWrist];
      final rElbow    = lm[PoseLandmarkType.rightElbow];
      final lElbow    = lm[PoseLandmarkType.leftElbow];
      final rShoulder = lm[PoseLandmarkType.rightShoulder];
      final lShoulder = lm[PoseLandmarkType.leftShoulder];

      if ([nose,rWrist,lWrist,rElbow,lElbow,rShoulder,lShoulder].any((e)=>e==null)) {
        _isDetecting = false; return;
      }

      final iw = image.width.toDouble();
      final ih = image.height.toDouble();
      double nx(double v) => v / iw;
      double ny(double v) => v / ih;
      double nz(double v) => v / iw;

      final hx  = nx(nose!.x),       hy  = ny(nose.y),       hz  = nz(nose.z);
      final rwx = nx(rWrist!.x),      rwy = ny(rWrist.y),     rwz = nz(rWrist.z);
      final lwx = nx(lWrist!.x),      lwy = ny(lWrist.y),     lwz = nz(lWrist.z);
      final rex = nx(rElbow!.x),      rey = ny(rElbow.y),     rez = nz(rElbow.z);
      final lex = nx(lElbow!.x),      ley = ny(lElbow.y),     lez = nz(lElbow.z);
      final rsx = nx(rShoulder!.x),   rsy = ny(rShoulder.y),  rsz = nz(rShoulder.z);
      final lsx = nx(lShoulder!.x),   lsy = ny(lShoulder.y),  lsz = nz(lShoulder.z);

      double d3d(double x1, double y1, double z1,
          double x2, double y2, double z2) =>
          math.sqrt((x1-x2)*(x1-x2)+(y1-y2)*(y1-y2)+(z1-z2)*(z1-z2));

      double ang(double dz, double dx) =>
          math.atan2(dz, dx) * 180 / math.pi;

      final features = Float32List.fromList([
        d3d(rwx,rwy,rwz, hx,hy,hz),
        rwz - hz,
        rwy / (hy + 1e-6),
        ang(rez - rsz, rex - rsx),
        rwx - _prevRWX,
        rwy - _prevRWY,
        rwz - _prevRWZ,
        d3d(lwx,lwy,lwz, hx,hy,hz),
        lwz - hz,
        lwy / (hy + 1e-6),
        ang(lez - lsz, lex - lsx),
        lwx - _prevLWX,
        lwy - _prevLWY,
        lwz - _prevLWZ,
      ]);

      _prevRWX = rwx; _prevRWY = rwy; _prevRWZ = rwz;
      _prevLWX = lwx; _prevLWY = lwy; _prevLWZ = lwz;

      // ONNX inference
      final tensor  = OrtValueTensor.createTensorWithDataList(features, [1, 14]);
      final results = await _ortSession!.runAsync(
        OrtRunOptions(), {'float_input': tensor},
      );
      tensor.release();

      final label = (results?[0]?.value as List)[0] as int;
      final probs = results?[1]?.value as List;
      final prob  = ((probs[0] as Map)[1] as double?) ?? 0.0;
      for (var r in results ?? []) { r?.release(); }

      if (label == 1) { _consecutive++; } else { _consecutive = 0; }
      final confirmed = _consecutive >= minConsecutive;

      setState(() {
        if (confirmed && !_prevIntake) _eventCount++;
        _prevIntake  = confirmed;
        _isIntake    = confirmed;
        _probability = prob;
      });

    } catch (e) {
      debugPrint('Error: $e');
    }
    _isDetecting = false;
  }

  InputImage? _toInputImage(CameraImage image) {
    final rotation = InputImageRotationValue.fromRawValue(
      _cameraController!.description.sensorOrientation,
    ) ?? InputImageRotation.rotation0deg;

    if (image.format.group != ImageFormatGroup.nv21) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size:        Size(image.width.toDouble(), image.height.toDouble()),
        rotation:    rotation,
        format:      InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _poseDetector?.close();
    _ortSession?.release();
    OrtEnv.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _cameraController?.value.isInitialized ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (ready) SizedBox.expand(child: CameraPreview(_cameraController!)),

          // Red border on intake
          if (_isIntake)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.redAccent, width: 6),
              ),
            ),

          // Top HUD
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.65),
              padding: const EdgeInsets.fromLTRB(16, 52, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isIntake ? 'INTAKE DETECTED!' : 'Normal',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: _isIntake ? Colors.redAccent : Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value:           _probability.clamp(0.0, 1.0),
                      minHeight:       12,
                      backgroundColor: Colors.grey[800],
                      valueColor:      AlwaysStoppedAnimation(
                        _probability > 0.5 ? Colors.redAccent : Colors.greenAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Probability: ${(_probability * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          // Bottom info
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.65),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _InfoBox(label: 'Events',      value: '$_eventCount'),
                  _InfoBox(label: 'Consecutive', value: '$_consecutive'),
                  _InfoBox(label: 'Prob %',      value: '${(_probability*100).toStringAsFixed(0)}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final String label;
  final String value;
  const _InfoBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: const TextStyle(
            fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
            fontSize: 12, color: Colors.white60)),
      ],
    );
  }
}
