// lib/main.dart
//
// 앱 엔트리포인트.
// 카메라 트래킹 로직 자체는 lib/screens/tracking_screen.dart 에 그대로 옮겨져 있고
// (기존 테스트용 main.dart 의 로직을 그대로 재사용),
// 이 파일은 로그인 → 홈(캘린더) → 약 상세/트래킹 → 설정으로 이어지는
// 전체 화면 흐름과 전역 상태(로그인 사용자)만 관리합니다.

import 'package:flutter/material.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const MicrostoneApp());
}

class MicrostoneApp extends StatefulWidget {
  const MicrostoneApp({super.key});

  @override
  State<MicrostoneApp> createState() => _MicrostoneAppState();
}

class _MicrostoneAppState extends State<MicrostoneApp> {
  final AppState _appState = AppState();

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      appState: _appState,
      child: MaterialApp(
        title: '약 복용 관리',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const LoginScreen(),
      ),
    );
  }
}
