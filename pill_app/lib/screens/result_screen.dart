import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';

// 결과 화면 — 서버에서 받은 탐지 결과를 카드 목록으로 표시하고
// 각 약에 대해 복약 알림을 등록할 수 있다
class ResultScreen extends StatelessWidget {
  // 서버 응답의 'detected' 배열 — 각 항목은 name, confidence, crop_image, info를 포함한다
  final List<dynamic> results;

  // 뒤로가기 버튼 클릭 시 MainPage에서 _results를 null로 초기화해 홈 화면으로 돌아간다
  final VoidCallback onBack;

  // 알림 저장 버튼 클릭 시 MainPage의 _schedules에 일정을 추가한다
  final void Function(Map<String, String> schedule) onAddSchedule;

  const ResultScreen({
    super.key,
    required this.results,
    required this.onBack,
    required this.onAddSchedule,
  });

  // 복약 알림 설정 다이얼로그
  // medicineName을 받아 복용량, 메모, 시간을 입력받은 뒤 onAddSchedule로 전달한다
  Future<void> _showAlarmDialog(BuildContext context, String medicineName) async {
    final dosageController = TextEditingController(text: '1정');
    final memoController = TextEditingController(text: '식후 30분');
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);

    await showDialog(
      context: context,
      builder: (dialogContext) {
        // StatefulBuilder를 사용해 다이얼로그 내부에서만 상태를 갱신한다
        // (시간 선택 후 버튼 라벨을 즉시 업데이트하기 위함)
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
                    // 시간 선택 버튼 — 선택 후 라벨이 즉시 업데이트된다
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

                    // MainPage의 _schedules에 새 알림을 추가한다
                    onAddSchedule({
                      'medicineName': medicineName,
                      'dosage': dosage.isEmpty ? '미입력' : dosage,
                      'memo': memo.isEmpty ? '-' : memo,
                      'time': timeText,
                    });

                    Navigator.pop(dialogContext);
                    // 저장 완료 스낵바 표시
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

    // 다이얼로그가 닫힌 후 컨트롤러 메모리 해제
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
          // 뒤로가기 → MainPage에서 _results를 null로 초기화해 홈 화면으로 전환
          onPressed: onBack,
        ),
      ),
      // results 배열의 각 항목을 _PillCard 위젯으로 변환해 리스트로 표시
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

// 탐지된 약 하나의 정보를 카드 형태로 표시하는 위젯
// crop_image(base64), name, confidence, info(약품명/효능/복용법/주의사항)를 표시한다
class _PillCard extends StatelessWidget {
  final Map<String, dynamic> pill;
  final void Function(String medicineName) onAlarmPressed;

  const _PillCard({required this.pill, required this.onAlarmPressed});

  @override
  Widget build(BuildContext context) {
    // info가 null이면 식약처 API 조회 실패 또는 미등록 약품
    final info = pill['info'] as Map<String, dynamic>?;

    // YOLO bbox 기준으로 잘라낸 약 이미지 (base64 인코딩)
    final cropB64 = pill['crop_image'] as String?;

    Uint8List? cropBytes;
    if (cropB64 != null && cropB64.isNotEmpty) {
      cropBytes = base64Decode(cropB64); // base64 → 바이트 배열로 변환해 Image.memory에 전달
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
                // YOLO가 탐지한 bbox 영역을 잘라낸 약 이미지
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
                      // 약품명 (YOLO 클래스명)
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
                          // 복약 알림 등록 버튼 → _showAlarmDialog 호출
                          ElevatedButton.icon(
                            onPressed: () => onAlarmPressed(pill['name'].toString()),
                            icon: const Icon(Icons.notifications),
                            label: const Text('복약 알림'),
                          ),
                          const SizedBox(height: 8),
                          // YOLO 모델의 탐지 신뢰도 (0~100%)
                          Chip(label: Text('신뢰도: ${pill['confidence']}%')),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),
            // 식약처 API에서 가져온 약 상세 정보
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

// 라벨(예: '효능')과 값을 세로로 쌓아 표시하는 정보 행 위젯
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
          // 라벨은 teal 색상으로 강조
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.teal)),
          // 긴 텍스트는 200자 기준으로 접어두고 더보기/접기 토글
          _ExpandableText(value ?? '정보 없음'),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// 200자 초과 텍스트를 접어두고 '...더보기' / '접기' 버튼으로 토글하는 위젯
// StatefulWidget을 사용해 expanded 상태를 자체적으로 관리한다
class _ExpandableText extends StatefulWidget {
  final String text;

  const _ExpandableText(this.text);

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  // 더보기/접기 기준 글자 수
  static const int _limit = 200;
  bool _expanded = false; // 현재 펼침 여부

  @override
  Widget build(BuildContext context) {
    final isLong = widget.text.length > _limit;
    // 펼치지 않았을 때는 _limit 글자까지만 표시
    final displayed = (!isLong || _expanded)
        ? widget.text
        : widget.text.substring(0, _limit);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(displayed),
        // 텍스트가 _limit을 초과하는 경우에만 더보기/접기 버튼 표시
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
