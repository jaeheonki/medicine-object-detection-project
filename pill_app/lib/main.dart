import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/result_screen.dart';
import 'screens/pill_list_screen.dart';
import 'screens/alarm_screen.dart';

// 앱의 진입점 — Flutter는 main() 함수에서 시작한다
void main() {
  runApp(const PillApp());
}

// 앱 전체를 감싸는 루트 위젯
// MaterialApp을 통해 테마와 기본 설정을 전역으로 적용한다
class PillApp extends StatelessWidget {
  const PillApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '약 정보 조회',
      debugShowCheckedModeBanner: false, // 디버그 배너 숨김
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const MainPage(),
    );
  }
}

// 하단 네비게이션 바와 화면 전환을 관리하는 메인 페이지
// 각 탭에서 공유해야 하는 상태(_results, _schedules)를 여기서 보관한다
// 자식 위젯(HomeScreen, ResultScreen 등)은 콜백을 통해 이 상태를 변경한다
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  // 현재 선택된 탭 인덱스 (0: 약 목록, 1: 홈, 2: 복약 알림)
  int _selectedIndex = 1; // 홈이 기본 탭 (가운데)

  // 분석 결과 목록
  // null이면 홈 화면을 표시하고, 값이 있으면 결과 화면으로 전환된다
  List<dynamic>? _results;

  // 등록된 복약 알림 목록
  // ResultScreen에서 알림을 추가하면 여기에 쌓이고, AlarmScreen에서 표시한다
  final List<Map<String, String>> _schedules = [];

  // 복약 알림 삭제 함수
  // AlarmScreen에서 삭제 버튼을 누르면 index를 받아 해당 일정을 제거한다
  void _cancelSchedule(int index) {
    setState(() {
      _schedules.removeAt(index);
    });
  }

  // 현재 탭 인덱스에 따라 표시할 화면 위젯을 반환한다
  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        // 약 목록 탭
        return const PillListScreen();

      case 1:
        // 홈 탭 — 분석 결과 유무에 따라 홈/결과 화면 전환
        if (_results == null) {
          // 분석 결과 없음 → 이미지 선택 및 분석 요청 화면
          return HomeScreen(
            // 분석 완료 시 결과를 받아 상태를 업데이트하면 결과 화면으로 전환된다
            onResults: (results) => setState(() => _results = results),
          );
        }

        // 분석 결과 있음 → 탐지된 약 카드 목록 화면
        return ResultScreen(
          results: _results!,
          // 뒤로가기 버튼 → _results를 null로 초기화해 홈 화면으로 돌아간다
          onBack: () => setState(() => _results = null),
          // 알림 추가 → _schedules 리스트에 새 일정을 추가한다
          onAddSchedule: (schedule) => setState(() => _schedules.add(schedule)),
        );

      case 2:
        // 복약 알림 탭 — 등록된 알림 목록 전달
        // onCancelSchedule을 통해 AlarmScreen에서 삭제 요청을 받는다
        return AlarmScreen(
          schedules: _schedules,
          onCancelSchedule: _cancelSchedule,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 탭에 따라 화면을 교체한다
      // Navigator.push 대신 상태 기반 전환을 사용해 하단 바가 항상 표시된다
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        // 탭 선택 시 인덱스를 업데이트하면 _buildBody()가 다시 호출된다
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