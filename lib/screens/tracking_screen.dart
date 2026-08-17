// lib/screens/tracking_screen.dart
//
// 기존 lib/main.dart (Server Test Client) 의 카메라 캡처 + Flask 서버 통신
// 로직을 그대로 가져와서, 특정 Medication 하나를 "복용 확인"하는 화면으로
// 재구성한 것입니다.
//
// 변경하지 않은 것 (사용자가 이미 테스트로 검증한 부분):
//   - camera.takePicture() 로 프레임을 찍어 멀티파트로 /predict 전송
//   - 요청 바디(session_id, frame), 응답 파싱(label/probability/consecutive/event_count/pose_detected)
//   - 400ms 캡처 주기
//
// 새로 추가한 것:
//   - 서버가 "label=1(확정 감지)"을 몇 번의 프레임에 걸쳐 연속으로 반환하는지를
//     클라이언트에서 시간으로 다시 한 번 재확인 (kIntakeConfirmDuration = 3초).
//     3초 이상 연속으로 감지되면 해당 약을 "복용 완료" 처리하고 화면을 닫습니다.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

import '../models/medication_model.dart';
import '../services/api_service.dart';
import '../services/app_config.dart';
import '../web_camera_helper.dart';

class TrackingScreen extends StatefulWidget {
  final Medication medication;
  const TrackingScreen({super.key, required this.medication});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  CameraController? _controller;
  Timer? _captureTimer;

  final String _sessionId = 'session-${DateTime.now().millisecondsSinceEpoch}';

  bool _busy = false;
  bool _isIntake = false;
  bool _poseDetected = false;
  double _probability = 0.0;
  int _eventCount = 0;
  int _consecutive = 0;
  String _status = '카메라 준비 중...';

  // 3초 연속 감지 확인용
  DateTime? _intakeStartedAt;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    List<CameraDescription> cameras = [];
    try {
      cameras = await safeAvailableCameras();
    } catch (e) {
      setState(() => _status = '카메라 목록을 가져오지 못했습니다: $e');
      return;
    }

    if (cameras.isEmpty) {
      setState(() => _status = '사용 가능한 카메라가 없습니다');
      return;
    }

    final front = cameras.first;

    _controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _status = '연결됨');
      _captureTimer = Timer.periodic(kCaptureInterval, (_) => _captureAndSend());
    } catch (e) {
      setState(() => _status = '카메라 초기화 실패: $e');
    }
  }

  Future<void> _captureAndSend() async {
    if (_finished) return;
    if (_busy || _controller == null || !_controller!.value.isInitialized) return;
    _busy = true;

    try {
      final XFile file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();

      final uri = Uri.parse('$kModelServerUrl/predict');
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
        final isIntakeNow = (data['label'] as int) == 1;

        if (mounted) {
          setState(() {
            _isIntake = isIntakeNow;
            _probability = (data['probability'] as num).toDouble();
            _consecutive = data['consecutive'] as int;
            _eventCount = data['event_count'] as int;
            _poseDetected = data['pose_detected'] as bool;
            _status = '연결됨';
          });
        }

        _evaluateIntakeDuration(isIntakeNow);
      } else {
        if (mounted) setState(() => _status = '서버 오류 ${streamed.statusCode}');
      }
    } catch (e) {
      if (mounted) setState(() => _status = '요청 실패: $e');
    } finally {
      _busy = false;
    }
  }

  /// 서버가 label=1 을 얼마나 연속으로 반환하는지 클라이언트에서 시간으로 측정.
  /// kIntakeConfirmDuration(3초) 이상 지속되면 "복용 완료"로 확정.
  void _evaluateIntakeDuration(bool isIntakeNow) {
    if (!isIntakeNow) {
      _intakeStartedAt = null;
      return;
    }

    _intakeStartedAt ??= DateTime.now();
    final elapsed = DateTime.now().difference(_intakeStartedAt!);

    if (elapsed >= kIntakeConfirmDuration && !_finished) {
      _finished = true;
      _completeIntake();
    }
  }

  Future<void> _completeIntake() async {
    _captureTimer?.cancel();
    try {
      await ApiService.instance.setMedicationDone(widget.medication.id, true);
    } catch (_) {
      // 실패해도 사용자 흐름은 이어가되, 목록 새로고침에서 재시도되게 함
    }
    if (!mounted) return;
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true); // true = 복용 확인됨
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
    final double progress = _intakeStartedAt == null
        ? 0.0
        : (DateTime.now().difference(_intakeStartedAt!).inMilliseconds /
                kIntakeConfirmDuration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();

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
                border: Border.all(color: const Color(0xFF735BF2), width: 6),
              ),
            ),

          // 상단 HUD
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
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                      Text(
                        widget.medication.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        kIsWeb ? 'WEB' : 'ANDROID',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isIntake ? '복용 동작 감지됨! 유지해주세요...' : '카메라에 복용 동작을 보여주세요',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _isIntake ? const Color(0xFF735BF2) : Colors.greenAccent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_status  •  pose: ${_poseDetected ? "감지됨" : "없음"}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // 하단 정보 + 3초 확정 progress bar
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              color: Colors.black.withOpacity(0.65),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _InfoBox(label: 'Events', value: '$_eventCount'),
                      _InfoBox(label: 'Consecutive', value: '$_consecutive'),
                      _InfoBox(label: 'Prob %', value: (_probability * 100).toStringAsFixed(0)),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: Colors.grey[800],
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF735BF2)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '3초 이상 유지되면 자동으로 복용 확인됩니다',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
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
            fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
            fontSize: 11, color: Colors.white60)),
      ],
    );
  }
}
