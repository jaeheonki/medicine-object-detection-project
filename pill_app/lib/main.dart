import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';

// 로컬 FastAPI 서버 주소 — 실제 기기에서 테스트할 때는 PC의 내부 IP로 변경 필요
const String apiUrl = 'http://localhost:9000/predict';

void main() {
  runApp(const PillApp());
}

// 앱 루트 위젯 — 테마 및 시작 화면 설정
class PillApp extends StatelessWidget {
  const PillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '약 정보 조회',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const PillHomePage(),
    );
  }
}

// 메인 화면 — 이미지 선택, 서버 분석 요청, 결과 표시를 담당
class PillHomePage extends StatefulWidget {
  const PillHomePage({super.key});

  @override
  State<PillHomePage> createState() => _PillHomePageState();
}

class _PillHomePageState extends State<PillHomePage> {
  Uint8List? _imageBytes;  // 선택한 이미지의 바이트 데이터
  String? _fileName;       // 선택한 이미지 파일명 (서버 전송 시 필요)
  List<dynamic> _results = [];  // 서버로부터 받은 탐지 결과 목록
  bool _loading = false;        // 서버 요청 중 여부 (버튼 비활성화 및 로딩 표시에 사용)
  String? _errorMessage;        // 서버 오류 또는 연결 실패 메시지

  // 갤러리 또는 카메라에서 이미지를 선택하고 상태를 업데이트
  // 웹에서는 source 구분 없이 파일 탐색기가 열림 — 실제 기기에서는 카메라/갤러리 구분됨
  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;

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
    if (_imageBytes == null || _fileName == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _results = [];
    });

    try {
      // multipart/form-data 형식으로 이미지 전송
      final request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        _imageBytes!,
        filename: _fileName!,
      ));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        setState(() => _results = data['detected']);
      } else {
        setState(() => _errorMessage = '서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _errorMessage = '연결 실패: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('약 정보 조회')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 선택한 이미지 미리보기
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_imageBytes!, height: 200, fit: BoxFit.contain),
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

            // 분석 버튼 — 이미지가 선택되지 않았거나 로딩 중이면 비활성화
            ElevatedButton.icon(
              onPressed: (_imageBytes != null && !_loading) ? _analyze : null,
              icon: _loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_loading ? '분석 중...' : '약 정보 조회'),
            ),
            const SizedBox(height: 16),

            // 오류 발생 시 빨간 텍스트로 표시
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),

            // 탐지된 약 목록을 카드로 렌더링
            ..._results.map((pill) => _PillCard(pill: pill)),
          ],
        ),
      ),
    );
  }
}

// 탐지된 약 하나의 정보를 카드 형태로 표시
// 서버 응답의 crop_image(base64)를 디코딩해 알약 이미지를 함께 보여줌
class _PillCard extends StatelessWidget {
  final Map<String, dynamic> pill;
  const _PillCard({required this.pill});

  @override
  Widget build(BuildContext context) {
    final info = pill['info'] as Map<String, dynamic>?;
    final cropB64 = pill['crop_image'] as String?;

    // 서버에서 받은 base64 문자열을 이미지 바이트로 변환
    Uint8List? cropBytes;
    if (cropB64 != null) {
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
                // 약품명 + 신뢰도 칩
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          pill['name'],
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Chip(label: Text('신뢰도: ${pill['confidence']}%')),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(),
            // 식약처 API로 조회한 약품 상세 정보
            if (info != null) ...[
              _InfoRow('약품명', info['약품명']),
              _InfoRow('효능', info['효능']),
              _InfoRow('복용법', info['복용법']),
              _InfoRow('주의사항', info['주의사항']),
            ] else
              const Text('정보를 찾을 수 없습니다.'),
          ],
        ),
      ),
    );
  }
}

// 라벨과 값을 세로로 쌓아 표시하는 정보 행
// 값이 길 경우 _ExpandableText가 접기/더보기를 처리
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

// 200자 초과 텍스트를 접어두고 '...더보기'로 펼칠 수 있는 위젯
class _ExpandableText extends StatefulWidget {
  final String text;
  const _ExpandableText(this.text);

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  static const int _limit = 200;  // 접힘 기준 글자 수
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
