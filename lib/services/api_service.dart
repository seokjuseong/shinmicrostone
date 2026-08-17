// lib/services/api_service.dart
//
// 회원가입/로그인/약 CRUD 를 담당하는 서비스 레이어입니다.
//
// 지금은 MySQL 백엔드가 아직 없기 때문에 메모리에만 저장해서 동작하지만,
// 메서드 시그니처(입출력)는 나중에 실제 REST API(MySQL 연동)를 붙일 때
// 그대로 쓸 수 있도록 만들어 두었습니다.
//
// ── 나중에 MySQL 백엔드가 준비되면 ──
// 1) 이 파일의 각 메서드 안의 "TODO(backend)" 부분을
//    http.post('$kBackendApiUrl/...') 형태로 교체하세요.
// 2) 예상 테이블 스키마:
//      users(id VARCHAR PK, password_hash VARCHAR, nickname VARCHAR)
//      medications(id VARCHAR PK, user_id VARCHAR FK, name VARCHAR,
//                   time VARCHAR, date DATE, is_done TINYINT, taken_at DATETIME)

import 'dart:async';
import 'dart:math';
import '../models/medication_model.dart';
import '../models/user_model.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  ApiService._internal();
  static final ApiService instance = ApiService._internal();

  // ── 메모리 저장소 (백엔드 대체용 임시 구현) ──
  final Map<String, _StoredUser> _users = {};
  final List<Medication> _medications = [];
  final Random _rng = Random();

  /// 로그인. id/pw 가 저장소에 있으면 성공.
  /// TODO(backend): POST $kBackendApiUrl/auth/login { id, password }
  Future<AppUser> login({required String id, required String password}) async {
    await _fakeLatency();
    final stored = _users[id];
    if (stored == null || stored.password != password) {
      throw ApiException('아이디 또는 비밀번호가 올바르지 않습니다.');
    }
    return AppUser(id: id, nickname: stored.nickname);
  }

  /// 회원가입.
  /// TODO(backend): POST $kBackendApiUrl/auth/signup { id, password, nickname }
  Future<AppUser> signUp({
    required String id,
    required String password,
    required String nickname,
  }) async {
    await _fakeLatency();
    if (id.isEmpty || password.isEmpty) {
      throw ApiException('아이디와 비밀번호를 입력해주세요.');
    }
    if (_users.containsKey(id)) {
      throw ApiException('이미 존재하는 아이디입니다.');
    }
    _users[id] = _StoredUser(password: password, nickname: nickname.isEmpty ? '사용자' : nickname);
    return AppUser(id: id, nickname: nickname.isEmpty ? '사용자' : nickname);
  }

  /// 회원 탈퇴 (해당 유저의 약 데이터도 함께 삭제)
  /// TODO(backend): DELETE $kBackendApiUrl/auth/users/{id}
  Future<void> withdraw(String userId) async {
    await _fakeLatency();
    _users.remove(userId);
    _medications.removeWhere((m) => true); // 데모용: 전체 초기화
  }

  /// 특정 날짜의 약 목록 조회.
  /// TODO(backend): GET $kBackendApiUrl/medications?user_id=...&date=...
  Future<List<Medication>> fetchMedications({
    required String userId,
    required DateTime date,
  }) async {
    await _fakeLatency();
    return _medications.where((m) => m.isOnDate(date)).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  /// 특정 달에 "복용 완료"된 약이 있는 날짜들 (캘린더 뱃지 표시용)
  /// TODO(backend): GET $kBackendApiUrl/medications/summary?user_id=...&year=...&month=...
  Future<Map<int, List<String>>> fetchMonthlyDoneSummary({
    required String userId,
    required int year,
    required int month,
  }) async {
    await _fakeLatency();
    final Map<int, List<String>> result = {};
    for (final m in _medications) {
      if (m.isDone && m.date.year == year && m.date.month == month) {
        result.putIfAbsent(m.date.day, () => []).add(m.name);
      }
    }
    return result;
  }

  /// 약 추가.
  /// TODO(backend): POST $kBackendApiUrl/medications { user_id, name, time, date }
  Future<Medication> addMedication({
    required String userId,
    required String name,
    required String time,
    required DateTime date,
  }) async {
    await _fakeLatency();
    final med = Medication(
      id: 'med_${DateTime.now().millisecondsSinceEpoch}_${_rng.nextInt(9999)}',
      name: name,
      time: time,
      date: DateTime(date.year, date.month, date.day),
    );
    _medications.add(med);
    return med;
  }

  /// 약 수정.
  /// TODO(backend): PUT $kBackendApiUrl/medications/{id} { name, time }
  Future<void> updateMedication({
    required String id,
    required String name,
    required String time,
  }) async {
    await _fakeLatency();
    final target = _medications.firstWhere((m) => m.id == id);
    target.name = name;
  }

  /// 약 삭제.
  /// TODO(backend): DELETE $kBackendApiUrl/medications/{id}
  Future<void> deleteMedication(String id) async {
    await _fakeLatency();
    _medications.removeWhere((m) => m.id == id);
  }

  /// 복용 여부 토글 (카메라 트래킹 성공 시 true 로 호출됨)
  /// TODO(backend): PATCH $kBackendApiUrl/medications/{id} { is_done, taken_at }
  Future<void> setMedicationDone(String id, bool done) async {
    await _fakeLatency();
    final target = _medications.firstWhere((m) => m.id == id);
    target.isDone = done;
    target.takenAt = done ? DateTime.now() : null;
  }

  Future<void> _fakeLatency() =>
      Future.delayed(const Duration(milliseconds: 120));
}

class _StoredUser {
  final String password;
  final String nickname;
  _StoredUser({required this.password, required this.nickname});
}
