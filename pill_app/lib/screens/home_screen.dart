import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// FastAPI 서버 주소 — 서버와 Flutter 앱이 같은 머신에서 실행될 때 사용
const String apiUrl = 'http://192.168.75.108:9000/predict';

// 홈 화면 — 이미지 선택 및 약 분석 요청을 담당한다
// 분석 결과는 onResults 콜백을 통해 MainPage로 전달되고,
// MainPage가 ResultScreen으로 화면을 전환한다
class HomeScreen extends StatefulWidget {
  final void Function(List<dynamic> results) onResults;
  final VoidCallback? onAlarmTap;
  final bool hasAlarms;

  const HomeScreen({super.key, required this.onResults, this.onAlarmTap, this.hasAlarms = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Uint8List? _imageBytes; // 선택한 이미지 바이트 (미리보기 + API 전송용)
  String? _fileName;      // 이미지 파일명 (YOLO가 확장자로 이미지 여부를 판단하므로 필수)
  bool _loading = false;
  String? _errorMessage;
  String _username = '사용자'; // 설정 화면에서 저장한 이름, 없으면 기본값

  // 테마 색상 — 컬러 차트 기준
  static const Color primaryColor   = Color(0xFF3629B7); // 메인 컬러
  static const Color bgColor        = Color(0xFFFAFAFA); // 배경 컬러
  static const Color cardColor      = Color(0xFFFFFFFF); // 흰색 컬러
  static const Color textHint       = Color(0xFF898989); // 본문·아이콘·버튼 테두리

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  // shared_preferences에서 이름을 불러온다
  // 설정 화면에서 이름을 변경한 뒤 홈 탭으로 돌아오면 반영된다
  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _username = prefs.getString('username') ?? '사용자');
  }

  // 갤러리 또는 카메라에서 이미지를 선택한다
  // 파일을 직접 전송하지 않고 bytes로 읽어 메모리에 보관한다
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

  // 선택한 이미지를 서버로 전송하고 탐지 결과를 받아온다
  // multipart/form-data 형식으로 전송하며, 결과는 onResults 콜백으로 상위 위젯에 전달한다
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
        preferredSize: Size.fromHeight(MediaQuery.of(context).padding.top + 56),
        child: Container(
          decoration: const BoxDecoration(
            color: primaryColor,
          ),
          padding: EdgeInsets.only(
              left: 20, right: 20,
              top: MediaQuery.of(context).padding.top + 12,
              bottom: 16),
          child: Row(
            children: [
              // 프로필 아바타 (현재는 기본 아이콘 고정, 추후 설정 사진 연동 가능)
              CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white24,
                child: const Icon(Icons.person, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              // 설정에서 저장한 이름으로 인사 문구 표시
              Text(
                '$_username님 안녕하세요',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // 알림 벨 아이콘 — 탭 시 복약 알림 탭으로 이동
              // 빨간 점은 현재 고정값 (추후 미읽은 알림 수 연동 가능)
              GestureDetector(
                onTap: widget.onAlarmTap,
                child: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined,
                        color: Colors.white, size: 26),
                    if (widget.hasAlarms)
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
                border: Border.all(color: textHint.withValues(alpha:0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha:0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              // 이미지 선택 전: 안내 텍스트 / 선택 후: 이미지 미리보기
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

            // ── 알약 찾기 버튼 — 이미지 미선택 또는 로딩 중이면 비활성화 ──
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: (_imageBytes != null && !_loading) ? _analyze : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  disabledBackgroundColor: const Color(0xFF898989).withValues(alpha:0.4),
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

            // ── 이미지 소스 선택 타일 ──
            _SourceTile(
              title: '갤러리에서 찾아오기',
              subtitle: '갤러리 이미지 버튼 클릭',
              icon: Icons.photo_outlined,
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            const SizedBox(height: 12),
            _SourceTile(
              title: '사진 직접 촬영하기',
              subtitle: '카메라 이미지 버튼 클릭',
              icon: Icons.camera_alt_outlined,
              onTap: () => _pickImage(ImageSource.camera),
            ),

            const SizedBox(height: 20),
            const Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 15, color: Color(0xFF343434)),
                children: [
                  TextSpan(text: '약들의 사진을 '),
                  TextSpan(
                    text: '앞면으로',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' 찍어서 업로드해주세요'),
                ],
              ),
              textAlign: TextAlign.center,
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

// 갤러리 / 카메라 선택 타일 위젯
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
          border: Border.all(color: const Color(0xFF898989).withValues(alpha:0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
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
                      color: Color(0xFF343434),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF585858),
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
                border: Border.all(color: const Color(0xFF898989).withValues(alpha:0.3)),
              ),
              child: Icon(icon, color: const Color(0xFF898989), size: 26),
            ),
          ],
        ),
      ),
    );
  }
}
