// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmWithdraw(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('회원 탈퇴', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('정말 탈퇴를 진행하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final appState = AppStateScope.of(context);
      final userId = appState.currentUser?.id;
      if (userId != null) {
        await ApiService.instance.withdraw(userId);
      }
      appState.logout();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AppStateScope.of(context).currentUser;

    return Column(
      children: [
        const SizedBox(height: 10),
        const Text('내 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark)),
        const SizedBox(height: 30),
        Container(
          width: 100,
          height: 100,
          decoration: const BoxDecoration(color: Color(0xFFD9DDFB), shape: BoxShape.circle),
          child: const Icon(Icons.person, size: 56, color: Color(0xFF4F5589)),
        ),
        const SizedBox(height: 16),
        Text(user?.nickname ?? '사용자',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark)),
        const SizedBox(height: 6),
        Text('@${user?.id ?? "user"}', style: const TextStyle(fontSize: 14, color: AppColors.textFaint)),
        const SizedBox(height: 40),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.cardBorder),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('아이디', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              Text(user?.id ?? 'user',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF212338))),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.dangerBorder),
                foregroundColor: AppColors.dangerText,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              onPressed: () => _confirmWithdraw(context),
              child: const Text('회원탈퇴'),
            ),
          ),
        ),
      ],
    );
  }
}
