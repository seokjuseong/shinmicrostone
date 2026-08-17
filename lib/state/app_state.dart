// lib/state/app_state.dart
//
// 로그인한 사용자 정보를 앱 전역에서 공유하기 위한 아주 단순한 상태 객체.
// (Provider 등 외부 패키지를 추가하지 않기 위해 ChangeNotifier + InheritedNotifier 조합만 사용)

import 'package:flutter/material.dart';
import '../models/user_model.dart';

class AppState extends ChangeNotifier {
  AppUser? currentUser;

  bool get isLoggedIn => currentUser != null;

  void setUser(AppUser user) {
    currentUser = user;
    notifyListeners();
  }

  void logout() {
    currentUser = null;
    notifyListeners();
  }
}

/// 하위 위젯 어디서든 AppState.of(context) 로 접근할 수 있게 해주는 InheritedNotifier.
class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState appState,
    required super.child,
  }) : super(notifier: appState);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'AppStateScope not found in context');
    return scope!.notifier!;
  }
}
