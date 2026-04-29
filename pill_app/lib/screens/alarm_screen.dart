import 'package:flutter/material.dart';

// 복약 알림 목록 화면 — 등록된 복약 일정 카드 표시
class AlarmScreen extends StatelessWidget {
  final List<Map<String, String>> schedules;

  const AlarmScreen({super.key, required this.schedules});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('복약 알림')),
      body: schedules.isEmpty
          ? const Center(
              child: Text(
                '등록된 복약 알림이 없습니다.\n약 분석 후 알림을 추가해보세요.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: schedules.length,
              itemBuilder: (context, index) {
                final s = schedules[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.alarm, color: Colors.teal, size: 36),
                    title: Text(
                      s['medicineName'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '복용량: ${s['dosage']}  |  시간: ${s['time']}\n메모: ${s['memo']}',
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
