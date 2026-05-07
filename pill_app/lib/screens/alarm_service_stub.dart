class NotificationService {
  static Future<void> init() async {}

  static Future<void> scheduleMedicineAlarm({
    required int id,
    required String medicineName,
    required DateTime dateTime,
  }) async {}

  static Future<void> cancelAlarm(int id) async {}
}