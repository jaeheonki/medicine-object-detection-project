import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:convert';

const String apiUrl = 'http://localhost:9000/predict';

void main() {
  runApp(const PillApp());
}

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

class PillHomePage extends StatefulWidget {
  const PillHomePage({super.key});

  @override
  State<PillHomePage> createState() => _PillHomePageState();
}

class _PillHomePageState extends State<PillHomePage> {
  Uint8List? _imageBytes;
  String? _fileName;
  List<dynamic> _results = [];
  bool _loading = false;
  String? _errorMessage;

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

  // FastAPI /predict 호출
  Future<void> _analyze() async {
    if (_imageBytes == null || _fileName == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _results = [];
    });

    try {
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
            // 이미지 미리보기
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_imageBytes!, height: 200, fit: BoxFit.contain),
              ),
            const SizedBox(height: 12),

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
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_loading ? '분석 중...' : '약 정보 조회'),
            ),
            const SizedBox(height: 16),

            // 에러 메시지
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),

            // 결과 카드
            ..._results.map((pill) => _PillCard(pill: pill)),
          ],
        ),
      ),
    );
  }
}

class _PillCard extends StatelessWidget {
  final Map<String, dynamic> pill;
  const _PillCard({required this.pill});

  @override
  Widget build(BuildContext context) {
    final info = pill['info'] as Map<String, dynamic>?;
    final cropB64 = pill['crop_image'] as String?;
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
                // 잘라낸 알약 이미지
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
                // 약품명 + 신뢰도
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
