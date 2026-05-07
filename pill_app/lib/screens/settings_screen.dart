import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

const Color _primary = Color(0xFF3629B7);

class SettingsScreen extends StatefulWidget {
  final void Function(double)? onFontSizeChanged;
  const SettingsScreen({super.key, this.onFontSizeChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _username = '사용자';
  String? _photoPath;
  double _fontSize = 14.0;
  int _photoKey = 0;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('username') ?? '사용자';
      _photoPath = prefs.getString('photo_path');
      _fontSize = prefs.getDouble('font_size') ?? 14.0;
    });
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final appDir = await getApplicationDocumentsDirectory();
    final dest = File('${appDir.path}/profile.jpg');

    // 기존 캐시 제거 후 파일 덮어쓰기
    if (dest.existsSync()) {
      await FileImage(dest).evict();
    }
    await File(picked.path).copy(dest.path);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('photo_path', dest.path);
    setState(() {
      _photoPath = dest.path;
      _photoKey++;
    });
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _username);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '이름을 입력하세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('저장', style: TextStyle(color: _primary)),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', result);
      setState(() => _username = result);
    }
  }

  Future<void> _editFontSize() async {
    double tempSize = _fontSize;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('폰트 크기 조절'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('미리보기 텍스트입니다.', style: TextStyle(fontSize: tempSize)),
              const SizedBox(height: 16),
              Slider(
                value: tempSize,
                min: 12.0,
                max: 20.0,
                divisions: 4,
                activeColor: _primary,
                label: '${tempSize.toStringAsFixed(0)}pt',
                onChanged: (v) => setDialogState(() => tempSize = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, tempSize),
              child: const Text('저장', style: TextStyle(color: _primary)),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('font_size', result);
      setState(() => _fontSize = result);
      widget.onFontSizeChanged?.call(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    const double avatarRadius = 52;
    final double statusBarH = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 파란 헤더 + 프로필 사진 겹침
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: _primary,
                ),
                padding: EdgeInsets.fromLTRB(20, statusBarH + 16, 20, avatarRadius + 40),
                child: const Text(
                  '환경설정',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                bottom: -avatarRadius,
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    key: ValueKey(_photoKey),
                    radius: avatarRadius,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: _photoPath != null
                        ? FileImage(File(_photoPath!))
                        : null,
                    child: _photoPath == null
                        ? const Icon(Icons.person, size: 52, color: Colors.white)
                        : null,
                  ),
                ),
              ),
            ],
          ),

          // 흰 카드 영역
          Expanded(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: avatarRadius),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 12,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Text(
                    _username,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _primary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _SettingTile(label: '폰트 크기 조절', onTap: _editFontSize),
                  _SettingTile(label: '이름 변경', onTap: _editName),
                  _SettingTile(label: '사진 변경', onTap: _pickPhoto),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SettingTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          minVerticalPadding: 16,
          title: Text(
            label,
            style: const TextStyle(fontSize: 18, color: Color(0xFF2D2D2D)),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 24),
          onTap: onTap,
        ),
        const Divider(height: 1, indent: 28, endIndent: 28, color: Color(0xFFEEEEEE)),
      ],
    );
  }
}
