import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// time zone
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Timezone 초기화 (zonedSchedule에 필요)
  tz.initializeTimeZones();

  // 2) LocalNotifications 초기화
  await NotificationService.instance.init();

  runApp(const MyApp());
}

//────────────────────────────────────────────────────────────────────────
// 싱글톤 NotificationService
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // 안드로이드 초기화
    const AndroidInitializationSettings androidInit =
    AndroidInitializationSettings('app_icon');
    // ↑ 'app_icon'은 android/app/src/main/res/drawable/app_icon.png (또는 mipmap)에 넣어야 함

    // iOS 초기화
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: true,
    );

    // 종합
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    // 초기화 실행
    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
    );
  }

  /// 스케줄된 알림 등록 (특정 DateTime에 노티 울림)
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    // 안드로이드 채널/알림 설정
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'alarm_channel_id',        // channel ID
      'Alarm Channel',           // channel name
      channelDescription: 'Repeated Alarm Notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    // iOS 설정
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    final NotificationDetails notiDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // zonedSchedule을 쓰려면 tz.TZDateTime 형태 필요
    final tz.TZDateTime tzTime = _toTZDateTime(scheduledTime);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      notiDetails,
      androidAllowWhileIdle: true,  // ← 이게 필수 파라미터가 되었습니다
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  // 예약취소 (모든 알림 취소)
  Future<void> cancelAll() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  /// DateTime -> tz.TZDateTime 변환
  tz.TZDateTime _toTZDateTime(DateTime dateTime) {
    final duration = dateTime.difference(DateTime.now());
    final tzNow = tz.TZDateTime.now(tz.local);
    return tzNow.add(duration);
  }
}

//────────────────────────────────────────────────────────────────────────
// Flutter UI 시작
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Notifications Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AlarmHomePage(),
    );
  }
}

//────────────────────────────────────────────────────────────────────────
class AlarmHomePage extends StatefulWidget {
  const AlarmHomePage({super.key});

  @override
  State<AlarmHomePage> createState() => _AlarmHomePageState();
}

class _AlarmHomePageState extends State<AlarmHomePage> {
  final TextEditingController _durationCtrl = TextEditingController();
  final TextEditingController _intervalCtrl = TextEditingController();

  bool _isRunning = false;
  int _remainingSeconds = 0;  // 총 남은 시간(초)
  int _repeatCount = 0;       // 총 몇 번 울려야 하는지
  int _alreadyRang = 0;       // 이미 울린 횟수

  Timer? _timer; // UI용 1초 카운트다운

  @override
  Widget build(BuildContext context) {
    final remMin = _remainingSeconds ~/ 60;
    final remSec = _remainingSeconds % 60;
    final remainRings = _repeatCount - _alreadyRang;

    return Scaffold(
      appBar: AppBar(title: const Text("알람 반복(Local Noti) 데모")),
      body: _isRunning
          ? _buildRunningView(remMin, remSec, remainRings)
          : _buildSetupView(),
    );
  }

  Widget _buildSetupView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextField(
            controller: _durationCtrl,
            keyboardType: TextInputType.number,
            decoration:
            const InputDecoration(labelText: "알람 지속 시간(분)"),
          ),
          TextField(
            controller: _intervalCtrl,
            keyboardType: TextInputType.number,
            decoration:
            const InputDecoration(labelText: "알람 간격(분)"),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _startAlarm,
            child: const Text("알람 시작"),
          ),
        ],
      ),
    );
  }

  Widget _buildRunningView(int remMin, int remSec, int remainRings) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            "알람 진행 중!\n"
                "총 $_repeatCount 회 중, 이미 $_alreadyRang 회 울림\n"
                "남은 횟수: $remainRings 회",
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            "남은 시간: ${remMin}분 ${remSec}초",
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _stopAlarm,
            child: const Text("알람 중지"),
          ),
        ],
      ),
    );
  }

  void _startAlarm() {
    final durationStr = _durationCtrl.text;
    final intervalStr = _intervalCtrl.text;
    final durationMin = int.tryParse(durationStr) ?? 0;
    final intervalMin = int.tryParse(intervalStr) ?? 0;

    if (durationMin <= 0 || intervalMin <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("양의 정수를 입력하세요.")),
      );
      return;
    }

    // 총 알람 횟수
    final totalCount = durationMin ~/ intervalMin;
    if (totalCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("지속 시간 >= 간격 이어야 합니다.")),
      );
      return;
    }

    setState(() {
      _isRunning = true;
      _remainingSeconds = durationMin * 60;
      _repeatCount = totalCount;
      _alreadyRang = 0;
    });

    // 1) 현재 시각
    final now = DateTime.now();

    // 2) 각 알람 시점을 예약
    for (int i = 1; i <= totalCount; i++) {
      final scheduledTime = now.add(Duration(minutes: intervalMin * i));
      _scheduleOneNotification(i, scheduledTime);
    }

    // 3) UI 갱신용 1초 타이머
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 0) {
        _onAlarmFinished();
      } else {
        setState(() {
          _remainingSeconds--;
        });
      }
    });
  }

  Future<void> _scheduleOneNotification(int index, DateTime scheduledTime) async {
    final notiId = 100 + index;
    final title = "알람! ($index번째)";
    final body =
        "${index}번째 알람 예정(${scheduledTime.hour}:${scheduledTime.minute}경)";

    await NotificationService.instance.scheduleNotification(
      id: notiId,
      title: title,
      body: body,
      scheduledTime: scheduledTime,
    );
  }

  void _stopAlarm() {
    // 모든 예약된 노티 취소
    NotificationService.instance.cancelAll();

    // 타이머 종료
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = 0;
      _repeatCount = 0;
      _alreadyRang = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("알람 중지됨")),
    );
  }

  void _onAlarmFinished() {
    _stopAlarm();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("알람이 종료되었습니다!")),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
