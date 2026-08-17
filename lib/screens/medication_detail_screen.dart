// lib/screens/medication_detail_screen.dart
//
// HTML 목업의 4번 화면(약 관리 상세)에 해당.
// 체크박스를 탭하면(미복용 상태일 때) 실제 카메라 트래킹 화면(TrackingScreen)으로 진입합니다.
// 원본 mockup 의 triggerCameraTracking(id) 자리에 실기능이 연결된 것입니다.

import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/api_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'tracking_screen.dart';

class MedicationDetailScreen extends StatefulWidget {
  final DateTime date;
  const MedicationDetailScreen({super.key, required this.date});

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  List<Medication> _meds = [];
  bool _loading = true;

  static const _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

  String get _userId => AppStateScope.of(context).currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final list = await ApiService.instance.fetchMedications(userId: _userId, date: widget.date);
    if (!mounted) return;
    setState(() {
      _meds = list;
      _loading = false;
    });
  }

  Future<void> _onCheckboxTap(Medication med) async {
    if (med.isDone) {
      // 이미 완료된 것을 다시 탭하면 취소 (원본 mockup 과 동일한 토글 동작)
      await ApiService.instance.setMedicationDone(med.id, false);
      _refresh();
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TrackingScreen(medication: med)),
    );
    if (result == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${med.name} 복용을 확인했습니다 ✅')),
      );
    }
    _refresh();
  }

  Future<void> _openMedForm({Medication? editing}) async {
    final nameCtrl = TextEditingController(text: editing?.name ?? '');
    TimeOfDay initialTime = TimeOfDay.now();
    if (editing != null) {
      final parts = editing.time.split(':');
      initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    }
    TimeOfDay pickedTime = initialTime;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    editing == null ? '약 추가' : '약 수정',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textDark),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameCtrl,
                    decoration: appInputDecoration('약 이름'),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () async {
                      final picked = await showTimePicker(context: ctx, initialTime: pickedTime);
                      if (picked != null) setModalState(() => pickedTime = picked);
                    },
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: AppColors.inputBg,
                        border: Border.all(color: AppColors.inputBorder),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(pickedTime.format(ctx)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('취소', style: TextStyle(color: AppColors.textMuted)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('약 이름을 입력해주세요.')),
                            );
                            return;
                          }
                          final timeStr =
                              '${pickedTime.hour.toString().padLeft(2, '0')}:${pickedTime.minute.toString().padLeft(2, '0')}';
                          if (editing == null) {
                            await ApiService.instance.addMedication(
                              userId: _userId, name: name, time: timeStr, date: widget.date,
                            );
                          } else {
                            await ApiService.instance.updateMedication(
                              id: editing.id, name: name, time: timeStr,
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        },
                        child: Text(editing == null ? '추가' : '수정'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved == true) _refresh();
  }

  Future<void> _confirmDelete(Medication med) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('약 삭제', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('약을 삭제하시겠습니까?'),
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
      await ApiService.instance.deleteMedication(med.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekdayLabel = _weekdayNames[widget.date.weekday - 1];
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 90,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.chevron_left, color: AppColors.textMuted),
          label: const Text('뒤로', style: TextStyle(color: AppColors.textMuted)),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${widget.date.month}월 ${widget.date.day}일 $weekdayLabel요일',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textDark),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      ..._meds.map(_buildMedCard),
                      _buildAddButton(),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedCard(Medication med) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.cardBorder, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _onCheckboxTap(med),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: med.isDone ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: med.isDone ? AppColors.primary : const Color(0xFFD5D8EE),
                  width: 2,
                ),
                shape: BoxShape.circle,
              ),
              child: med.isDone
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  med.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: med.isDone ? AppColors.textMuted : const Color(0xFF212338),
                    decoration: med.isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(med.time, style: const TextStyle(fontSize: 13, color: Color(0xFF8A8EA5))),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppColors.textMuted),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onSelected: (value) {
              if (value == 'edit') _openMedForm(editing: med);
              if (value == 'delete') _confirmDelete(med);
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'edit', child: Text('✏️  수정')),
              PopupMenuItem(value: 'delete', child: Text('🗑️  삭제', style: TextStyle(color: AppColors.dangerText))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return InkWell(
      onTap: () => _openMedForm(),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        height: 60,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFB8BCF2), width: 1.5, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Text(
          '＋  약 추가',
          style: TextStyle(color: AppColors.primary, fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
