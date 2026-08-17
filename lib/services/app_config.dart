// lib/services/app_config.dart
//
// 서버 주소 등 환경설정을 한 곳에 모아둡니다.
// 실행 시 --dart-define 으로 덮어쓸 수 있습니다. 예:
//   flutter run -d chrome --dart-define=MODEL_SERVER_URL=http://localhost:5000

/// 복용 판별 모델(Flask) 서버 주소.
/// main.dart 테스트 때 쓰던 kServerBaseUrl 과 동일한 역할입니다.
/// - Chrome(웹)에서 같은 PC의 Flask 서버를 쓸 때: http://localhost:5000
/// - Android 에뮬레이터에서 PC의 Flask 서버를 쓸 때: http://10.0.2.2:5000
/// - 다른 기기/실기기: http://<PC-LAN-IP>:5000
const String kModelServerUrl = String.fromEnvironment(
  'MODEL_SERVER_URL',
  defaultValue: 'http://localhost:5000',
);

/// 회원/약 데이터를 다룰 백엔드(추후 MySQL 연동) 서버 주소.
/// 아직 백엔드가 없으므로 지금은 ApiService 가 이 값을 사용하지 않고
/// 메모리에만 저장합니다. 백엔드가 준비되면 이 값만 바꾸고
/// ApiService 내부의 TODO 부분을 실제 http 호출로 교체하면 됩니다.
const String kBackendApiUrl = String.fromEnvironment(
  'BACKEND_API_URL',
  defaultValue: 'http://localhost:8000',
);

/// 카메라 프레임 캡처 주기 (main.dart 와 동일)
const Duration kCaptureInterval = Duration(milliseconds: 400);

/// "복용했다"고 확정 짓기 위한 연속 감지 시간.
/// (요청하신 "3초 이상" 기준. kCaptureInterval 로 나눠 프레임 수를 계산합니다.)
const Duration kIntakeConfirmDuration = Duration(seconds: 3);
