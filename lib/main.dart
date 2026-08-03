// lib/main.dart
//
// Medication Intake Detection - Server Test Client
// Works on BOTH:
//   - flutter run -d chrome        (Web)
//   - flutter run                  (Android emulator/device)
// with the EXACT same code path, because it uses camera.takePicture()
// (supported on web + android) instead of startImageStream (android-only)
// and sends frames to a Flask server for inference instead of
// ML Kit + onnxruntime on-device.
//
// pubspec.yaml dependencies needed:
//   camera: ^0.10.5+9
//   http: ^1.2.0
//   permission_handler: ^11.3.0   (android only, safe to keep for both)
//
// SERVER URL:
//   - Android emulator -> Flask on your PC:      http://10.0.2.2:5000
//   - Chrome (web) on the SAME PC as Flask:       http://localhost:5000
//   - Real device / Chrome on ANOTHER machine:    http://<PC-LAN-IP>:5000
//   Change kServerBaseUrl below accordingly, or pass --dart-define=SERVER_URL=...

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'web_camera_helper.dart';
import 'package:http/http.dart' as http;

// ── Change this to match your setup (see comment block above) ──
const String kServerBaseUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://localhost:5000', // default: Android emulator target
);

const Duration kCaptureInterval = Duration(milliseconds: 400);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await safeAvailableCameras();

  runApp(
    MyApp(cameras: cameras),
  );
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medication Tracker (Server Test)',
      theme: ThemeData.dark(),
      home: MedicationTestScreen(cameras: cameras),
    );
  }
}

class MedicationTestScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const MedicationTestScreen({super.key, required this.cameras});

  @override
  State<MedicationTestScreen> createState() => _MedicationTestScreenState();
}

class _MedicationTestScreenState extends State<MedicationTestScreen> {
  CameraController? _controller;
  Timer? _captureTimer;

  final String _sessionId =
      'test-${DateTime.now().millisecondsSinceEpoch}';

  bool _busy = false;
  bool _isIntake = false;
  bool _poseDetected = false;
  double _probability = 0.0;
  int _eventCount = 0;
  int _consecutive = 0;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() => _status = 'No camera found');
      return;
    }

    // On web, lensDirection is often unknown, so fall back to the first camera.
    final front = widget.cameras.first;

    _controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      setState(() => _status = 'Connected');
      _captureTimer = Timer.periodic(kCaptureInterval, (_) => _captureAndSend());
    } catch (e) {
      setState(() => _status = 'Camera init failed: $e');
    }
  }

  Future<void> _captureAndSend() async {
    if (_busy || _controller == null || !_controller!.value.isInitialized) return;
    _busy = true;

    try {
      final XFile file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();

      final uri = Uri.parse('$kServerBaseUrl/predict');
      final request = http.MultipartRequest('POST', uri)
        ..fields['session_id'] = _sessionId
        ..files.add(http.MultipartFile.fromBytes(
          'frame',
          bytes,
          filename: 'frame.jpg',
        ));

      final streamed = await request.send().timeout(const Duration(seconds: 5));
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _isIntake = (data['label'] as int) == 1;
            _probability = (data['probability'] as num).toDouble();
            _consecutive = data['consecutive'] as int;
            _eventCount = data['event_count'] as int;
            _poseDetected = data['pose_detected'] as bool;
            _status = 'Connected';
          });
        }
      } else {
        if (mounted) setState(() => _status = 'Server error ${streamed.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Request failed: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller?.value.isInitialized ?? false;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (ready)
            SizedBox.expand(child: CameraPreview(_controller!))
          else
            Center(
              child: Text(_status, style: const TextStyle(color: Colors.white)),
            ),

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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isIntake ? 'INTAKE DETECTED!' : 'Normal',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _isIntake ? Colors.redAccent : Colors.greenAccent,
                        ),
                      ),
                      Text(
                        kIsWeb ? 'WEB' : 'ANDROID',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_status  •  pose: ${_poseDetected ? "detected" : "none"}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _probability.clamp(0.0, 1.0),
                      minHeight: 12,
                      backgroundColor: Colors.grey[800],
                      valueColor: AlwaysStoppedAnimation(
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
                  _InfoBox(label: 'Events', value: '$_eventCount'),
                  _InfoBox(label: 'Consecutive', value: '$_consecutive'),
                  _InfoBox(label: 'Prob %', value: (_probability * 100).toStringAsFixed(0)),
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
