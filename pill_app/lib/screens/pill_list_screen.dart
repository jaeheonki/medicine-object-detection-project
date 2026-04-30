import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String _baseUrl = 'http://localhost:9000';

// 인식 가능한 약 목록 화면
// 서버의 /classes 엔드포인트에서 약품명 리스트를 가져와 카드 형태로 표시한다
// 각 카드에서 '상세정보' 버튼을 누르면 /pill-info/{name}으로 상세 정보를 로드한다
class PillListScreen extends StatefulWidget {
  const PillListScreen({super.key});

  @override
  State<PillListScreen> createState() => _PillListScreenState();
}

class _PillListScreenState extends State<PillListScreen> {
  List<String> _classes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/classes'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _classes = List<String>.from(data['classes']);
          _loading = false;
        });
      } else {
        setState(() {
          _error = '서버 오류: ${response.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = '연결 실패: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('인식 가능한 약 목록')),
        body: Center(child: Text(_error!, style: const TextStyle(color: Colors.red))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F7FF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '알약 찾기 결과',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black87, size: 30),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
        itemCount: _classes.length,
        itemBuilder: (context, index) => _PillCard(name: _classes[index]),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF3626B8),
        shape: const CircleBorder(),
        onPressed: () {
          // TODO: 카메라 / 이미지 업로드 기능 연결
        },
        child: const Icon(Icons.add, color: Colors.white, size: 36),
      ),
    );
    }
  }
// 약품 카드 — 상세정보 버튼을 즉시 표시하고, 클릭 시에만 API를 호출한다
// 리스트 로드 시 56개 동시 API 호출을 방지하기 위해 on-demand 방식을 사용한다
class _PillCard extends StatefulWidget {
  final String name;
  const _PillCard({required this.name});

  @override
  State<_PillCard> createState() => _PillCardState();
}

class _PillCardState extends State<_PillCard> {
  Map<String, dynamic>? _cachedInfo; // 한 번 로드한 정보를 캐시해 재클릭 시 재호출 방지

  Future<void> _showDetail(BuildContext context) async {
    // 이미 캐시된 정보가 있으면 API 재호출 없이 바로 표시
    if (_cachedInfo != null) {
      _openDialog(context, _cachedInfo!);
      return;
    }

    // 로딩 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final encoded = Uri.encodeComponent(widget.name);
      final response = await http.get(Uri.parse('$_baseUrl/pill-info/$encoded'));
      if (!context.mounted) return;
      Navigator.pop(context); // 로딩 다이얼로그 닫기

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final info = data['info'] as Map<String, dynamic>?;
        if (info != null) {
          _cachedInfo = info;
          _openDialog(context, info);
        } else {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(widget.name),
              content: const Text('정보를 찾을 수 없습니다.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
              ],
            ),
          );
        }
      }
    } catch (_) {
      if (context.mounted) Navigator.pop(context);
    }
  }

  void _openDialog(BuildContext context, Map<String, dynamic> info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(info['약품명']?.toString() ?? widget.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow('효능', info['효능']?.toString()),
              _DetailRow('복용법', info['복용법']?.toString()),
              _DetailRow('주의사항', info['주의사항']?.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  return Container(
    margin: const EdgeInsets.only(bottom: 18),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _placeholder(),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '알약에 관한 내용 알약내용입니다. 복용법과 주의사항을 확인할 수 있습니다.',
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF8A8A8A),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => _showDetail(context),
                child: const Text(
                  '...더보기',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A8A8A),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _placeholder() {
  return Container(
    width: 120,
    height: 120,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFE9E9E9),
      borderRadius: BorderRadius.circular(14),
    ),
    child: const Text(
      '알약 사진',
      style: TextStyle(
        color: Color(0xFF999999),
        fontSize: 15,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

} // end of _PillCardState

// 상세정보 다이얼로그 내 라벨-값 행 위젯
class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 4),
          _ExpandableText(value ?? '정보 없음'),
        ],
      ),
    );
  }
}

// 200자 초과 텍스트를 접어두고 '...더보기' / '접기' 버튼으로 토글하는 위젯
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
