// lib/models/medication_model.dart
//
// 약 데이터 모델.
// 지금은 메모리에만 저장되지만, 나중에 MySQL 백엔드가 생기면
// 이 클래스의 필드가 그대로 테이블 컬럼(id, user_id, name, time, date, is_done)에
// 매핑되도록 설계했습니다.

class Medication {
  final String id;
  String name;
  final String time; // "HH:mm" 형식
  final DateTime date; // 해당 약이 속한 날짜 (연/월/일만 의미 있음)
  bool isDone;
  DateTime? takenAt;

  Medication({
    required this.id,
    required this.name,
    required this.time,
    required this.date,
    this.isDone = false,
    this.takenAt,
  });

  /// 같은 날짜인지 비교할 때 사용 (연/월/일만 비교)
  bool isOnDate(DateTime other) {
    return date.year == other.year &&
        date.month == other.month &&
        date.day == other.day;
  }

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'].toString(),
      name: json['name'] as String,
      time: json['time'] as String,
      date: DateTime.parse(json['date'] as String),
      isDone: (json['is_done'] as bool?) ?? false,
      takenAt: json['taken_at'] != null
          ? DateTime.tryParse(json['taken_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'time': time,
        'date': '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}',
        'is_done': isDone,
        'taken_at': takenAt?.toIso8601String(),
      };
}
