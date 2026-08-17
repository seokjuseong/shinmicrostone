// lib/screens/home_calendar_screen.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'medication_detail_screen.dart';

class HomeCalendarScreen extends StatefulWidget {
  const HomeCalendarScreen({super.key});

  @override
  State<HomeCalendarScreen> createState() => _HomeCalendarScreenState();
}

class _HomeCalendarScreenState extends State<HomeCalendarScreen> {
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<int, List<String>> _doneSummary = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // AppStateScope.of(context) 는 initState 시점엔 안전하지 않으므로
    // 첫 프레임이 그려진 직후로 미룹니다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSummary());
  }

  String get _userId => AppStateScope.of(context).currentUser?.id ?? '';

  Future<void> _loadSummary() async {
    setState(() => _loading = true);
    final userId = AppStateScope.of(context).currentUser?.id ?? '';
    final summary = await ApiService.instance.fetchMonthlyDoneSummary(
      userId: userId,
      year: _visibleMonth.year,
      month: _visibleMonth.month,
    );
    if (!mounted) return;
    setState(() {
      _doneSummary = summary;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
    _loadSummary();
  }

  Future<void> _openDate(DateTime date) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MedicationDetailScreen(date: date)),
    );
    _loadSummary(); // 복용 표시가 바뀌었을 수 있으니 새로고침
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final firstDayOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    // 월요일 시작 기준으로 앞의 빈 칸 개수 (Dart weekday: 월=1 ... 일=7)
    final leadingEmpty = firstDayOfMonth.weekday - 1;
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;

    return Column(
      children: [
        const SizedBox(height: 8),
        // 상단: 월 이동 헤더
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, color: AppColors.textMuted),
              onPressed: () => _changeMonth(-1),
            ),
            const SizedBox(width: 12),
            Text(
              '${_visibleMonth.month}월',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textDark),
            ),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: AppColors.textMuted),
              onPressed: () => _changeMonth(1),
            ),
          ],
        ),

        // "약 먹기" 버튼: 오늘 날짜의 약 목록으로 바로 이동 (거기서 카메라 트래킹 시작)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: primaryButtonStyle(),
              onPressed: () => _openDate(today),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('약 먹기'),
            ),
          ),
        ),

        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: 7 + leadingEmpty + daysInMonth,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio: 0.72,
                  ),
                  itemBuilder: (context, index) {
                    // 요일 라벨 행
                    if (index < 7) {
                      const labels = ['월', '화', '수', '목', '금', '토', '일'];
                      Color color = AppColors.textMuted;
                      if (index == 5) color = AppColors.saturday;
                      if (index == 6) color = AppColors.sunday;
                      return Center(
                        child: Text(labels[index],
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                      );
                    }

                    final cellIndex = index - 7;
                    if (cellIndex < leadingEmpty) return const SizedBox.shrink();

                    final day = cellIndex - leadingEmpty + 1;
                    if (day > daysInMonth) return const SizedBox.shrink();

                    final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
                    final weekday = date.weekday; // 1=월 ... 7=일
                    final isToday = date.year == today.year &&
                        date.month == today.month &&
                        date.day == today.day;
                    final badges = _doneSummary[day] ?? const [];

                    Color numColor = AppColors.textDark;
                    if (weekday == 6) numColor = AppColors.saturday;
                    if (weekday == 7) numColor = AppColors.sunday;

                    return InkWell(
                      onTap: () => _openDate(date),
                      child: Container(
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: Color(0xFFF0F2FA), width: 0.5),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: isToday
                                  ? const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)
                                  : null,
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isToday ? Colors.white : numColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            ...badges.take(2).map((name) => Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECEEFF),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF8F94B5),
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
