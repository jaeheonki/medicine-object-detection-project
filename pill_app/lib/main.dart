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

// 탭 인덱스: 0 리스트 / 1 홈 / 2 복약알림 / 3 설정
const Color _primaryColor = Color(0xFF3629B7);
const Color _cardColor    = Color(0xFFFFFFFF);
const Color _textHint     = Color(0xFF898989);

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 1; // 홈이 기본 탭

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
          return HomeScreen(
            onResults: (results) => setState(() => _results = results),
            onAlarmTap: () => setState(() => _selectedIndex = 2),
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
        return AlarmScreen(
          schedules: _schedules,
          onCancelSchedule: _cancelSchedule,
        );

      case 3:
        return const Center(child: Text('설정 화면 준비 중'));

      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildBody(),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: _cardColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: _primaryColor,
          unselectedItemColor: _textHint,
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.medication_outlined),
              label: '약 목록',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded),
              label: '홈',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.alarm_outlined),
              label: '복약 알림',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}