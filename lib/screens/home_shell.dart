// lib/screens/home_shell.dart
//
// HTML 목업의 하단 탭바(도감/홈/설정)를 그대로 옮긴 뼈대 화면.

import 'package:flutter/material.dart';
import '../theme.dart';
import 'home_calendar_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tabIndex = 1; // 0: 도감, 1: 홈, 2: 설정

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _EncyclopediaPlaceholder(),
      const HomeCalendarScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _tabIndex, children: pages)),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textMuted,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), label: '도감'),
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: '설정'),
        ],
      ),
    );
  }
}

class _EncyclopediaPlaceholder extends StatelessWidget {
  const _EncyclopediaPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('도감 화면 (준비 중)', style: TextStyle(color: AppColors.textMuted)),
    );
  }
}
