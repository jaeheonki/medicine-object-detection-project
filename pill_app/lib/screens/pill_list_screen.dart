import 'package:flutter/material.dart';

// 인식 가능한 약 목록 화면
// 현재는 준비 중 상태이며, 추후 YOLO 모델이 탐지 가능한 약 클래스 목록(dataset.yaml 기준)을 표시할 예정이다
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
