import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/result_screen.dart';
import 'screens/pill_list_screen.dart';
import 'screens/alarm_screen.dart';

void main() {
  runApp(const PillApp());
}

// 앱 루트 위젯 — 테마 설정
class PillApp extends StatelessWidget {
  const PillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '약 정보 조회',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const MainPage(),
    );
  }
}

// 하단 네비게이션을 포함한 전체 틀
// 탭 전환 및 공유 상태(_results, _schedules)를 관리한다
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 1; // 홈이 기본 탭 (가운데)

  // 분석 결과 — null이면 홈 화면, 값이 있으면 결과 화면 표시
  List<dynamic>? _results;

  // 등록된 복약 알림 목록 — result_screen과 alarm_screen이 공유
  final List<Map<String, String>> _schedules = [];

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const PillListScreen();
      case 1:
        // 분석 결과가 없으면 홈, 있으면 결과 화면
        if (_results == null) {
          return HomeScreen(
            onResults: (results) => setState(() => _results = results),
          );
        }
        return ResultScreen(
          results: _results!,
          onBack: () => setState(() => _results = null),
          onAddSchedule: (schedule) => setState(() => _schedules.add(schedule)),
        );
      case 2:
        return AlarmScreen(schedules: _schedules);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.medication),
            label: '약 목록',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.alarm),
            label: '복약 알림',
          ),
        ],
      ),
    );
  }
}
