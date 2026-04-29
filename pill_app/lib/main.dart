import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// 로컬 FastAPI 서버 주소
// 실제 기기에서 테스트할 때는 localhost 대신 PC의 내부 IP로 변경해야 함
const String apiUrl = 'http://localhost:9000/predict';

void main() {
  runApp(const PillApp());
}

// 앱 루트 위젯
class PillApp extends StatelessWidget {
  const PillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '약 정보 조회',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const PillHomePage(),
    );
  }
}

// 메인 화면
// 이미지 선택, 서버 분석 요청, 결과 표시, 복약 알림 등록을 담당
class PillHomePage extends StatefulWidget {
  const PillHomePage({super.key});

  @override
  State<PillHomePage> createState() => _PillHomePageState();
}

class _PillHomePageState extends State<PillHomePage> {
  Uint8List? _imageBytes; // 선택한 이미지 바이트 데이터
  String? _fileName; // 선택한 이미지 파일명

  List<dynamic> _results = []; // 서버로부터 받은 탐지 결과 목록
  bool _loading = false; // 서버 요청 중 여부
  String? _errorMessage; // 오류 메시지

  // 등록된 복약 알림 목록
  final List<Map<String, String>> _schedules = [];

  // 갤러리 또는 카메라에서 이미지를 선택하고 상태를 업데이트
  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);

    if (picked == null) {
      return;
    }

    final bytes = await picked.readAsBytes();

    setState(() {
      _imageBytes = bytes;
      _fileName = picked.name;
      _results = [];
      _errorMessage = null;
    });
  }

  // 선택한 이미지를 FastAPI /predict 엔드포인트로 전송하고 결과를 받아옴
  Future<void> _analyze() async {
    if (_imageBytes == null || _fileName == null) {
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
      _results = [];
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(apiUrl),
      );

      // 백엔드 코드가 image: UploadFile = File(...) 로 받는 구조이므로 필드명을 image로 사용
      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          _imageBytes!,
          filename: _fileName!,
        ),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);

        setState(() {
          _results = data['detected'] ?? [];
        });
      } else {
        setState(() {
          _errorMessage = '서버 오류: ${response.statusCode}\n$body';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '연결 실패: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // 약 복용 알림 설정 다이얼로그
  Future<void> _showMedicineAlarmDialog(String medicineName) async {
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

                        if (pickedTime == null) {
                          return;
                        }

                        setDialogState(() {
                          selectedTime = pickedTime;
                        });
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text('복약 시간 선택: $timeText'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('취소'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final dosage = dosageController.text.trim();
                    final memo = memoController.text.trim();

                    setState(() {
                      _schedules.add({
                        'medicineName': medicineName,
                        'dosage': dosage.isEmpty ? '미입력' : dosage,
                        'memo': memo.isEmpty ? '-' : memo,
                        'time': timeText,
                      });

                      _errorMessage = null;
                    });

                    Navigator.pop(dialogContext);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '$medicineName 복용 알림이 $timeText에 등록되었습니다.',
                        ),
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

  // 등록된 복약 알림 목록 표시
  Widget _buildScheduleList() {
    if (_schedules.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '등록된 복약 알림',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ..._schedules.map((schedule) {
              return ListTile(
                leading: const Icon(Icons.notifications),
                title: Text(
                  '${schedule['time']} - ${schedule['medicineName']}',
                ),
                subtitle: Text(
                  '복용량: ${schedule['dosage']}\n메모: ${schedule['memo']}',
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('약 정보 조회'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 선택한 이미지 미리보기
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),

            const SizedBox(height: 12),

            // 갤러리 / 카메라 선택 버튼
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo),
                    label: const Text('갤러리'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('카메라'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // 분석 버튼
            ElevatedButton.icon(
              onPressed: (_imageBytes != null && !_loading) ? _analyze : null,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_loading ? '분석 중...' : '약 정보 조회'),
            ),

            const SizedBox(height: 16),

            // 오류 메시지
            if (_errorMessage != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ),

            // 탐지된 약 목록 카드
            ..._results.map(
              (pill) => _PillCard(
                pill: Map<String, dynamic>.from(pill),
                onAlarmPressed: _showMedicineAlarmDialog,
              ),
            ),

            // 등록된 복약 알림 목록
            _buildScheduleList(),
          ],
        ),
      ),
    );
  }
}

// 탐지된 약 하나의 정보를 카드 형태로 표시
class _PillCard extends StatelessWidget {
  final Map<String, dynamic> pill;
  final void Function(String medicineName) onAlarmPressed;

  const _PillCard({
    required this.pill,
    required this.onAlarmPressed,
  });

  @override
  Widget build(BuildContext context) {
    final info = pill['info'] as Map<String, dynamic>?;
    final cropB64 = pill['crop_image'] as String?;

    // 서버에서 받은 base64 문자열을 이미지 바이트로 변환
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
                    child: Image.memory(
                      cropBytes,
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                    ),
                  ),

                if (cropBytes != null) const SizedBox(width: 12),

                // 약품명 + 복용 알림 버튼 + 신뢰도 칩
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          pill['name'].toString(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(width: 8),

                      // 사용자가 검정색으로 표시한 오른쪽 상단 영역
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              onAlarmPressed(pill['name'].toString());
                            },
                            icon: const Icon(Icons.notifications),
                            label: const Text('약 복용 알림'),
                          ),
                          const SizedBox(height: 8),
                          Chip(
                            label: Text('신뢰도: ${pill['confidence']}%'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Divider(),

            // 식약처 API로 조회한 약품 상세 정보
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
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.teal,
            ),
          ),
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
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            child: Text(
              _expanded ? '접기' : '...더보기',
              style: const TextStyle(
                color: Colors.teal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}