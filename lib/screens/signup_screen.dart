// lib/screens/signup_screen.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _nickCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    _nickCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiService.instance.signUp(
        id: _idCtrl.text.trim(),
        password: _pwCtrl.text,
        nickname: _nickCtrl.text.trim(),
      );
      if (!mounted) return;
      // 원본 목업과 동일하게: 가입 후 로그인 화면으로 복귀
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원가입이 완료되었습니다. 로그인해주세요.')),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Text(
              '앱 이 름',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textFaint,
              ),
            ),
            const SizedBox(height: 60),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  TextField(controller: _idCtrl, decoration: appInputDecoration('아이디')),
                  const SizedBox(height: 16),
                  TextField(controller: _pwCtrl, obscureText: true, decoration: appInputDecoration('비밀번호')),
                  const SizedBox(height: 16),
                  TextField(controller: _nickCtrl, decoration: appInputDecoration('닉네임')),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppColors.dangerText, fontSize: 13)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: primaryButtonStyle(),
                  onPressed: _loading ? null : _handleJoin,
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text('확인'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
