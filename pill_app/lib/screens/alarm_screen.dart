import 'package:flutter/material.dart';

// 복약 알림 목록 화면
class AlarmScreen extends StatelessWidget {
  final List<Map<String, String>> schedules;
  final void Function(int index) onCancelSchedule;

  const AlarmScreen({
    super.key,
    required this.schedules,
    required this.onCancelSchedule,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFC),
      body: SafeArea(
        child: Column(
          children: [
            const _AlarmTopBar(),

            Expanded(
              child: schedules.isEmpty
                  ? const Center(
                      child: Text(
                        '등록된 복약 알림이 없습니다.\n약 분석 후 알림을 추가해보세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF9A9A9A),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                      itemCount: schedules.length,
                      separatorBuilder: (context, index) {
                        return const SizedBox(height: 20);
                      },
                      itemBuilder: (context, index) {
                        final s = schedules[index];

                        return AlarmCard(
                          medicineName: s['medicineName'] ?? '알약 이름1',
                          time: s['time'] ?? '09:00',
                          dosage: s['dosage'] ?? '1정',
                          memo: s['memo'] ?? '식후 30분',
                          dateTime: s['dateTime'] ?? '2026/04/08 9:50',
                          onDelete: () {
                            final medicineName = s['medicineName'] ?? '복약';

                            onCancelSchedule(index);

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$medicineName 복약 일정이 취소되었습니다.'),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlarmTopBar extends StatelessWidget {
  const _AlarmTopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Stack(
        children: [
          Positioned(
            left: 14,
            top: 17,
            child: GestureDetector(
              onTap: () {
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
              },
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 17,
                color: Colors.black,
              ),
            ),
          ),

          const Positioned(
            left: 40,
            top: 15,
            child: Text(
              '알림',
              style: TextStyle(
                fontSize: 18,
                height: 1.0,
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const Positioned(
            right: 24,
            top: 22,
            child: Text(
              '삭제하려면 왼쪽으로 밀어주세요',
              style: TextStyle(
                fontSize: 11,
                height: 1.0,
                color: Color(0x66888888),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AlarmCard extends StatelessWidget {
  final String medicineName;
  final String time;
  final String dosage;
  final String memo;
  final String dateTime;
  final VoidCallback onDelete;

  const AlarmCard({
    super.key,
    required this.medicineName,
    required this.time,
    required this.dosage,
    required this.memo,
    required this.dateTime,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('$medicineName-$time-$dateTime'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        onDelete();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
        ),
      ),
      child: Container(
        height: 150,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 18,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: 0,
              top: 0,
              child: Text(
                medicineName,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.0,
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            Positioned(
              left: 0,
              top: 34,
              child: const _LabelText('복용 시간'),
            ),
            Positioned(
              right: 0,
              top: 34,
              child: _ValueText(time),
            ),

            Positioned(
              left: 0,
              top: 58,
              child: const _LabelText('복용 개수'),
            ),
            Positioned(
              right: 0,
              top: 58,
              child: _ValueText(dosage),
            ),

            Positioned(
              left: 0,
              top: 82,
              child: const _LabelText('공복 여부'),
            ),
            Positioned(
              right: 0,
              top: 82,
              child: _ValueText(memo),
            ),

            Positioned(
              left: 0,
              top: 106,
              child: const _LabelText('복용 일시'),
            ),
            Positioned(
              right: 0,
              top: 106,
              child: _ValueText(dateTime),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelText extends StatelessWidget {
  final String text;

  const _LabelText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        height: 1.0,
        color: Color(0xFF9A9A9A),
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _ValueText extends StatelessWidget {
  final String text;

  const _ValueText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      style: const TextStyle(
        fontSize: 11,
        height: 1.0,
        color: Color(0xFF3948FF),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}