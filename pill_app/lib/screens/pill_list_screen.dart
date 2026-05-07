import 'dart:convert';

import 'package:flutter/material.dart';
import '../pill_image_map.dart';
import 'package:http/http.dart' as http;

const String _baseUrl = 'http://192.168.75.108:9000';

class PillListScreen extends StatefulWidget {
  const PillListScreen({super.key});

  @override
  State<PillListScreen> createState() => _PillListScreenState();
}

class _PillListScreenState extends State<PillListScreen> {
  List<String> _classes = [];
  bool _loading = true;
  String? _error;
  bool _isSearching = false;
  String _query = '';
  final _searchController = TextEditingController();

  List<String> get _filtered => _query.isEmpty
      ? _classes
      : _classes.where((name) => name.toLowerCase().contains(_query.toLowerCase())).toList();

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeName(String value) {
    return value
        .replaceAll(RegExp(r'[^0-9a-zA-Z가-힣ㄱ-ㅎㅏ-ㅣᄀ-ᇿ]'), '')
        .toLowerCase();
  }

  Future<void> _loadClasses() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/classes'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final classes = List<String>.from(data['classes']);

        setState(() {
          _classes = classes;
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
        body: Center(
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF3629B7),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: '약품명 검색...',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text(
                '알약 찾기 결과',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white, size: 30),
            onPressed: () => setState(() {
              _isSearching = !_isSearching;
              if (!_isSearching) {
                _query = '';
                _searchController.clear();
              }
            }),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
        itemCount: _filtered.length,
        itemBuilder: (context, index) {
          final name = _filtered[index];
          final imagePath = pillImagePathByName[_normalizeName(name)];

          return _PillCard(
            name: name,
            imagePath: imagePath,
          );
        },
      ),
    );
  }
}

class _PillCard extends StatefulWidget {
  final String name;
  final String? imagePath;

  const _PillCard({
    required this.name,
    required this.imagePath,
  });

  @override
  State<_PillCard> createState() => _PillCardState();
}

class _PillCardState extends State<_PillCard> {
  Map<String, dynamic>? _cachedInfo;

  Future<void> _showDetail(BuildContext context) async {
    if (_cachedInfo != null) {
      _openDialog(context, _cachedInfo!);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final uri = Uri.parse('$_baseUrl/pill-info')
          .replace(queryParameters: {'name': widget.name});
      final response = await http.get(uri);
      if (!context.mounted) return;
      Navigator.pop(context);

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
          _pillImage(),
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
                  '알약에 관한 내용입니다. 복용법과 주의사항을 확인할 수 있습니다.',
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
                      color: Color(0xFF3626B8),
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

  Widget _pillImage() {
    final imagePath = widget.imagePath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 120,
        height: 120,
        color: const Color(0xFFE9E9E9),
        child: imagePath == null
            ? const Center(
                child: Text(
                  '알약 사진',
                  style: TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : Image.asset(
                imagePath,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
      ),
    );
  }
}

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
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 4),
          _ExpandableText(value ?? '정보 없음'),
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
