import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/home_screen.dart';
import 'screens/result_screen.dart';
import 'screens/pill_list_screen.dart';
import 'screens/alarm_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/alarm_service.dart';
import 'screens/splash.dart';

// 앱의 진입점 — Flutter는 main() 함수에서 시작한다
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();

  runApp(const PillApp());
}

// 앱 전체를 감싸는 루트 위젯
// 폰트 크기 상태를 보관하고 MaterialApp의 textScaler에 연결한다
class PillApp extends StatefulWidget {
  const PillApp({super.key});

  @override
  State<PillApp> createState() => _PillAppState();
}

class _PillAppState extends State<PillApp> {
  double _fontSize = 14.0;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then(
      (p) => setState(() => _fontSize = p.getDouble('font_size') ?? 14.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '약 정보 조회',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      // 앱 전체 텍스트 크기를 기본값(14) 대비 비율로 조정
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(_fontSize / 14.0),
        ),
        child: child!,
      ),
      home: SplashScreen(
        onFontSizeChanged: (size) => setState(() => _fontSize = size),
      ),
    );
  }
}

// 하단 네비게이션 바와 화면 전환을 관리하는 메인 페이지
// 각 탭에서 공유해야 하는 상태(_results, _schedules)를 여기서 보관한다
// 자식 위젯(HomeScreen, ResultScreen 등)은 콜백을 통해 이 상태를 변경한다
class MainPage extends StatefulWidget {
  final void Function(double) onFontSizeChanged;
  const MainPage({super.key, required this.onFontSizeChanged});

  @override
  State<MainPage> createState() => _MainPageState();
}

// 탭 인덱스: 0 리스트 / 1 홈 / 2 복약알림 / 3 설정
const Color _primaryColor = Color(0xFF3629B7);
const Color _cardColor = Color(0xFFFFFFFF);
const Color _textHint = Color(0xFF898989);

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 1; // 홈이 기본 탭

  // 분석 결과 목록
  // null이면 홈 화면을 표시하고, 값이 있으면 결과 화면으로 전환된다
  List<dynamic>? _results;

  // 등록된 복약 알림 목록
  // ResultScreen에서 알림을 추가하면 여기에 쌓이고, AlarmScreen에서 표시한다
  final List<Map<String, String>> _schedules = [];

  // 복약 알림 추가 함수
  // 화면에 일정을 추가하는 것뿐 아니라 실제 휴대폰 알림도 예약한다
  void _addSchedule(Map<String, String> schedule) async {
    final alarmId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final alarmDateTime = _parseScheduleDateTime(schedule);

    final savedSchedule = Map<String, String>.from(schedule);
    savedSchedule['id'] = alarmId.toString();
    savedSchedule['dateTime'] = _formatDateTime(alarmDateTime);

    setState(() {
      _schedules.add(savedSchedule);
    });

    await NotificationService.scheduleMedicineAlarm(
      id: alarmId,
      medicineName: savedSchedule['medicineName'] ?? '복약',
      dateTime: alarmDateTime,
    );
  }

  // 복약 알림 삭제 함수
  // AlarmScreen에서 삭제하면 화면 목록에서 제거하고 실제 예약 알림도 취소한다
  void _cancelSchedule(int index) async {
    if (index < 0 || index >= _schedules.length) return;

    final schedule = _schedules[index];
    final alarmIdText = schedule['id'];

    if (alarmIdText != null) {
      final alarmId = int.tryParse(alarmIdText);

      if (alarmId != null) {
        await NotificationService.cancelAlarm(alarmId);
      }
    }

    if (!mounted) return;

    setState(() {
      _schedules.removeAt(index);
    });
  }

  // schedule에 들어있는 dateTime 또는 time 값을 DateTime으로 변환한다
  DateTime _parseScheduleDateTime(Map<String, String> schedule) {
    final dateTimeText = schedule['dateTime']?.trim();

    // 예: 2026/04/08 9:50 또는 2026-04-08 09:50
    if (dateTimeText != null && dateTimeText.isNotEmpty) {
      final parsedDateTime = _tryParseDateTimeText(dateTimeText);

      if (parsedDateTime != null) {
        return parsedDateTime;
      }
    }

    // dateTime이 없거나 파싱 실패하면 time만 사용
    // 예: 09:00
    final timeText = schedule['time']?.trim() ?? '09:00';
    final timeParts = timeText.split(':');

    final hour = int.tryParse(timeParts[0]) ?? 9;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;

    final now = DateTime.now();

    var alarmDateTime = DateTime(
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // 이미 지난 시간이면 다음 날 알림으로 예약
    if (alarmDateTime.isBefore(now)) {
      alarmDateTime = alarmDateTime.add(const Duration(days: 1));
    }

    return alarmDateTime;
  }

  // 문자열 날짜를 DateTime으로 변환한다
  DateTime? _tryParseDateTimeText(String text) {
    final normalized = text.replaceAll('/', '-');

    final regex = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{1,2})',
    );

    final match = regex.firstMatch(normalized);

    if (match == null) return null;

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);
    final hour = int.tryParse(match.group(4)!);
    final minute = int.tryParse(match.group(5)!);

    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      return null;
    }

    return DateTime(year, month, day, hour, minute);
  }

  // AlarmScreen에 보여줄 날짜 문자열 생성
  String _formatDateTime(DateTime dateTime) {
    final year = dateTime.year.toString();
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$year/$month/$day $hour:$minute';
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
            hasAlarms: _schedules.isNotEmpty,
          );
        }

        // 분석 결과 있음 → 탐지된 약 카드 목록 화면
        return ResultScreen(
          results: _results!,
          // 뒤로가기 버튼 → _results를 null로 초기화해 홈 화면으로 돌아간다
          onBack: () => setState(() => _results = null),
          // 알림 추가 → 화면 목록에 저장하고 실제 알림도 예약한다
          onAddSchedule: _addSchedule,
        );

      case 2:
        return AlarmScreen(
          schedules: _schedules,
          onCancelSchedule: _cancelSchedule,
        );

      case 3:
        return SettingsScreen(
          onFontSizeChanged: widget.onFontSizeChanged,
        );

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
