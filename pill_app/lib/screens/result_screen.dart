import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';

// 결과 화면 — 서버에서 받은 탐지 결과를 카드 목록으로 표시하고
// 각 약에 대해 복약 알림을 등록할 수 있다
class ResultScreen extends StatefulWidget {
  final List<dynamic> results;
  final VoidCallback onBack;
  final void Function(Map<String, String> schedule) onAddSchedule;

  const ResultScreen({
    super.key,
    required this.results,
    required this.onBack,
    required this.onAddSchedule,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _isSearching = false;
  String _query = '';
  final _searchController = TextEditingController();

  List<dynamic> get _filtered => _query.isEmpty
      ? widget.results
      : widget.results
          .where((p) => p['name'].toString().toLowerCase().contains(_query.toLowerCase()))
          .toList();

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
                    widget.onAddSchedule({
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
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF3629B7),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: '약품명 검색...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text(
                '알약 찾기 결과',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: widget.onBack,
        ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _query = '';
                _searchController.clear();
              }
            }),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 24, 16),
        children: _filtered
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


    return Stack(
      clipBehavior: Clip.none,
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 20),
          color: Colors.white,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 약품명
                Text(
                  pill['name'].toString(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이미지 + 신뢰도 칩
                    Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: cropBytes != null
                              ? Image.memory(cropBytes, width: 110, height: 110, fit: BoxFit.cover)
                              : Container(
                                  width: 110,
                                  height: 110,
                                  color: Colors.grey[200],
                                  child: const Icon(Icons.medication, color: Colors.grey, size: 40),
                                ),
                        ),
                        const SizedBox(height: 6),
                        Chip(
                          label: Text('신뢰도: ${pill['confidence']}%',
                              style: const TextStyle(fontSize: 11)),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // 효능/복용법/주의사항 라벨별 표시
                    Expanded(
                      child: info != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _InfoRow('효능', info['효능']?.toString()),
                                _InfoRow('복용법', info['복용법']?.toString()),
                                _InfoRow('주의사항', info['주의사항']?.toString()),
                              ],
                            )
                          : const Text('정보를 찾을 수 없습니다.'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // 복약 알림 등록 버튼 — 카드 우상단에 배치
        Positioned(
          top: 0,
          right: -4,
          child: ElevatedButton.icon(
            onPressed: () => onAlarmPressed(pill['name'].toString()),
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text('알림 추가', style: TextStyle(fontSize: 14, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3730A3),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ),
      ],
    );
  }
}


// 라벨과 값을 세로로 표시하는 정보 행 위젯
class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.teal, fontSize: 12)),
          _ExpandableText(value ?? '정보 없음'),
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
