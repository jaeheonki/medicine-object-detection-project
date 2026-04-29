import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// FastAPI 서버 주소 — 서버와 Flutter 앱이 같은 머신에서 실행될 때 사용
// 실제 배포 시에는 서버 IP 또는 도메인으로 변경해야 한다
const String apiUrl = 'http://localhost:9000/predict';

// 홈 화면 — 이미지 선택 및 서버 분석 요청을 담당한다
// 분석이 완료되면 onResults 콜백으로 결과를 MainPage에 전달하고,
// MainPage가 ResultScreen으로 화면을 전환한다
class HomeScreen extends StatefulWidget {
  // 분석 결과를 MainPage로 전달하는 콜백
  final void Function(List<dynamic> results) onResults;

  const HomeScreen({super.key, required this.onResults});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? _imageBytes; // 선택된 이미지의 바이트 데이터 (미리보기에 사용)
  String? _fileName;      // 선택된 이미지 파일명 (서버 업로드 시 필요)
  bool _loading = false;  // 분석 요청 중 여부 (버튼 비활성화 및 인디케이터 표시)
  String? _errorMessage;  // 오류 발생 시 화면에 표시할 메시지

  // 갤러리 또는 카메라에서 이미지를 선택한다
  // source에 ImageSource.gallery 또는 ImageSource.camera를 전달한다
  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return; // 사용자가 선택 취소한 경우
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _fileName = picked.name;
      _errorMessage = null; // 이전 오류 메시지 초기화
    });
  }

  // 선택된 이미지를 서버로 전송하고 분석 결과를 받아온다
  Future<void> _analyze() async {
    if (_imageBytes == null || _fileName == null) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      // multipart/form-data 형식으로 이미지를 업로드한다
      final request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.files.add(http.MultipartFile.fromBytes(
        'image',       // FastAPI 엔드포인트의 파라미터명과 일치해야 함
        _imageBytes!,
        filename: _fileName!,
      ));
      final response = await request.send();
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        final data = jsonDecode(body);
        // 성공 시 MainPage의 onResults 콜백을 호출해 결과 화면으로 전환
        widget.onResults(data['detected'] ?? []);
      } else {
        setState(() => _errorMessage = '서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      // 서버가 꺼져있거나 네트워크 오류 발생 시
      setState(() => _errorMessage = '연결 실패: $e');
    } finally {
      // 성공/실패 상관없이 로딩 상태 해제
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('약 정보 조회')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '약 정보 조회',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),
            // 이미지를 선택한 경우 미리보기 표시
            if (_imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_imageBytes!, height: 200, fit: BoxFit.contain),
              ),
              const SizedBox(height: 24),
            ],
            // 갤러리 / 카메라 선택 버튼 (웹에서는 카메라도 파일탐색기로 연결됨)
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
            const SizedBox(height: 12),
            // 분석 버튼 — 이미지가 선택된 경우에만 활성화된다
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
            // 오류 발생 시 메시지 표시
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
