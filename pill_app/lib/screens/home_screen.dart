import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// FastAPI 서버 주소 — 서버와 Flutter 앱이 같은 머신에서 실행될 때 사용
const String apiUrl = 'http://localhost:9000/predict';

class HomeScreen extends StatefulWidget {
  final void Function(List<dynamic> results) onResults;
  final VoidCallback? onAlarmTap;

  const HomeScreen({super.key, required this.onResults, this.onAlarmTap});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? _imageBytes;
  String? _fileName;
  bool _loading = false;
  String? _errorMessage;

  // 테마 색상 — 컬러 차트 기준
  static const Color primaryColor   = Color(0xFF3629B7); // 메인 컬러
  static const Color bgColor        = Color(0xFFFAFAFA); // 배경 컬러
  static const Color cardColor      = Color(0xFFFFFFFF); // 흰색 컬러
  static const Color textMain       = Color(0xFF343434); // 메인 글씨
  static const Color textSub        = Color(0xFF585858); // 서브 글씨
  static const Color textHint       = Color(0xFF898989); // 본문·아이콘·버튼 테두리

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _fileName = picked.name;
      _errorMessage = null;
    });
  }

  Future<void> _analyze() async {
    if (_imageBytes == null || _fileName == null) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
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
        widget.onResults(data['detected'] ?? []);
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
      backgroundColor: bgColor,
      // ───────────────────────────── 상단 헤더 ─────────────────────────────
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(
            color: primaryColor,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(
              left: 20, right: 20, top: 40, bottom: 12),
          child: Row(
            children: [
              // 프로필 아바타
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white24,
                child: const Icon(Icons.person, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                '안녕하세요, 00님',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 알림 벨 아이콘 — 탭 시 복약 알림 탭으로 이동
              GestureDetector(
                onTap: widget.onAlarmTap,
                child: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined,
                        color: Colors.white, size: 26),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // ─────────────────────────────── 본문 ────────────────────────────────
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 이미지 미리보기 박스 ──
            Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 180, maxHeight: 260),
            child: Container(
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: textHint.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _imageBytes != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(_imageBytes!,
                          fit: BoxFit.contain),
                    )
                  : Center(
                      child: Text(
                        '등록한 이미지 또는 칸',
                        style: TextStyle(
                          color: textHint,
                          fontSize: 15,
                        ),
                      ),
                    ),
            ),
            ),
            ),
            const SizedBox(height: 20),

            // ── 알약 찾기 버튼 ──
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: (_imageBytes != null && !_loading) ? _analyze : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  disabledBackgroundColor: const Color(0xFF898989).withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : const Text(
                        '알약 찾기',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // ── 갤러리에서 찾아오기 ──
            _SourceTile(
              title: '갤러리에서 찾아오기',
              subtitle: '갤러리 이미지 버튼 클릭',
              icon: Icons.photo_outlined,
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            const SizedBox(height: 12),

            // ── 사진 직접 촬영하기 ──
            _SourceTile(
              title: '사진 직접 촬영하기',
              subtitle: '카메라 이미지 버튼 클릭',
              icon: Icons.camera_alt_outlined,
              onTap: () => _pickImage(ImageSource.camera),
            ),

            // ── 오류 메시지 ──
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),

    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 갤러리 / 카메라 선택 타일 위젯
// ─────────────────────────────────────────────────────────────────────────────
class _SourceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SourceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF898989).withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF343434), // 메인 글씨
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF585858), // 서브 글씨
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF898989).withOpacity(0.3)),
              ),
              child: Icon(icon,
                  color: const Color(0xFF898989), size: 26),
            ),
          ],
        ),
      ),
    );
  }
}
