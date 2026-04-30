import 'package:flutter/material.dart';

// 복약 알림 목록 화면
// MainPage의 _schedules 리스트를 받아 등록된 복약 일정을 카드로 표시한다
// 알림 추가는 ResultScreen의 '복약 알림' 버튼에서 진행한다
class AlarmScreen extends StatelessWidget {
  // MainPage에서 관리하는 복약 일정 목록
  // ResultScreen에서 알림을 추가할 때마다 이 리스트가 갱신된다
  final List<Map<String, String>> schedules;

  // 삭제 버튼 클릭 시 MainPage의 _schedules에서 해당 일정을 제거한다
  final void Function(int index) onCancelSchedule;

  const AlarmScreen({
    super.key,
    required this.schedules,
    required this.onCancelSchedule,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('복약 알림')),
      body: schedules.isEmpty
          // 등록된 알림이 없는 경우 안내 문구 표시
          ? const Center(
              child: Text(
                '등록된 복약 알림이 없습니다.\n약 분석 후 알림을 추가해보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          // 알림이 있는 경우 카드 목록으로 표시
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: schedules.length,
              itemBuilder: (context, index) {
                final s = schedules[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(
                      Icons.alarm,
                      color: Colors.teal,
                      size: 36,
                    ),

                    // 약품명
                    title: Text(
                      s['medicineName'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),

                    // 복용량, 복약 시간, 메모
                    subtitle: Text(
                      '복용량: ${s['dosage']}  |  시간: ${s['time']}\n메모: ${s['memo']}',
                    ),
                    isThreeLine: true,

                    // 복약 일정 취소 버튼
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '복약 일정 취소',
                      onPressed: () {
                        final medicineName = s['medicineName'] ?? '복약';

                        onCancelSchedule(index);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$medicineName 복약 일정이 취소되었습니다.'),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}