import 'package:flutter/material.dart';

// 인식 가능한 약 목록 화면 — 모델이 탐지할 수 있는 약 클래스 목록 표시
class PillListScreen extends StatelessWidget {
  const PillListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('인식 가능한 약 목록')),
      body: const Center(
        child: Text(
          '준비 중입니다.',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }
}
