import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';

// 결과 화면 — 탐지된 약 카드 목록 표시 및 복약 알림 등록 담당
class ResultScreen extends StatelessWidget {
  final List<dynamic> results;
  final VoidCallback onBack;
  final void Function(Map<String, String> schedule) onAddSchedule;

  const ResultScreen({
    super.key,
    required this.results,
    required this.onBack,
    required this.onAddSchedule,
  });

  // 복약 알림 설정 다이얼로그
  Future<void> _showAlarmDialog(BuildContext context, String medicineName) async {
    final dosageController = TextEditingController(text: '1정');
    final memoController = TextEditingController(text: '식후 30분');
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final timeText =
                '${selectedTime.hour.toString().padLeft(2, '0')}:'
                '${selectedTime.minute.toString().padLeft(2, '0')}';

            return AlertDialog(
              title: Text('$medicineName 복용 알림 설정'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: dosageController,
                      decoration: const InputDecoration(
                        labelText: '복용량',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: memoController,
                      decoration: const InputDecoration(
                        labelText: '메모',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final pickedTime = await showTimePicker(
                          context: dialogContext,
                          initialTime: selectedTime,
                        );
                        if (pickedTime == null) return;
                        setDialogState(() => selectedTime = pickedTime);
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text('복약 시간 선택: $timeText'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final timeText =
                        '${selectedTime.hour.toString().padLeft(2, '0')}:'
                        '${selectedTime.minute.toString().padLeft(2, '0')}';
                    final dosage = dosageController.text.trim();
                    final memo = memoController.text.trim();

                    onAddSchedule({
                      'medicineName': medicineName,
                      'dosage': dosage.isEmpty ? '미입력' : dosage,
                      'memo': memo.isEmpty ? '-' : memo,
                      'time': timeText,
                    });

                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$medicineName 복용 알림이 $timeText에 등록되었습니다.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );

    dosageController.dispose();
    memoController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('분석 결과'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: results
            .map((pill) => _PillCard(
                  pill: Map<String, dynamic>.from(pill),
                  onAlarmPressed: (name) => _showAlarmDialog(context, name),
                ))
            .toList(),
      ),
    );
  }
}

// 탐지된 약 하나의 정보를 카드 형태로 표시
class _PillCard extends StatelessWidget {
  final Map<String, dynamic> pill;
  final void Function(String medicineName) onAlarmPressed;

  const _PillCard({required this.pill, required this.onAlarmPressed});

  @override
  Widget build(BuildContext context) {
    final info = pill['info'] as Map<String, dynamic>?;
    final cropB64 = pill['crop_image'] as String?;

    Uint8List? cropBytes;
    if (cropB64 != null && cropB64.isNotEmpty) {
      cropBytes = base64Decode(cropB64);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // YOLO bbox 기준으로 잘라낸 알약 이미지
                if (cropBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(cropBytes, width: 90, height: 90, fit: BoxFit.cover),
                  ),
                if (cropBytes != null) const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          pill['name'].toString(),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => onAlarmPressed(pill['name'].toString()),
                            icon: const Icon(Icons.notifications),
                            label: const Text('복약 알림'),
                          ),
                          const SizedBox(height: 8),
                          Chip(label: Text('신뢰도: ${pill['confidence']}%')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),
            if (info != null) ...[
              _InfoRow('약품명', info['약품명']?.toString()),
              _InfoRow('효능', info['효능']?.toString()),
              _InfoRow('복용법', info['복용법']?.toString()),
              _InfoRow('주의사항', info['주의사항']?.toString()),
            ] else
              const Text('정보를 찾을 수 없습니다.'),
          ],
        ),
      ),
    );
  }
}

// 라벨과 값을 세로로 쌓아 표시하는 정보 행
class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.teal)),
          _ExpandableText(value ?? '정보 없음'),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// 200자 초과 텍스트를 접어두고 더보기/접기를 처리하는 위젯
class _ExpandableText extends StatefulWidget {
  final String text;

  const _ExpandableText(this.text);

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  static const int _limit = 200;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > _limit;
    final displayed = (!isLong || _expanded)
        ? widget.text
        : widget.text.substring(0, _limit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(displayed),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? '접기' : '...더보기',
              style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
