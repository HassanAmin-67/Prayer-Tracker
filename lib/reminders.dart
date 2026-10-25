import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'prayer_logic.dart';

class AzaanOption {
  const AzaanOption(this.id, this.name);
  final String id; // also the file name in android/app/src/main/res/raw
  final String name; // what you see in the app
}

// To add another azaan: put the .mp3 in res/raw (name: lowercase, starts
// with "azaan_") and add one line here.
const azaanOptions = [
  AzaanOption('azaan_makkah', 'Makkah'),
];

const modeOff = 0;
const modeNotification = 1;
const modeAzaan = 2; // full azaan
const modeShort = 3; // only the first few seconds

// How long the short azaan plays before it is cut off
const shortAzaanSeconds = 6;

const _names = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

// ---------- saved choices ----------
int reminderMode(SharedPreferences p, int i) =>
    p.getInt('reminder_mode_$i') ?? modeNotification;

Future<void> saveReminderMode(SharedPreferences p, int i, int mode) async {
  await p.setInt('reminder_mode_$i', mode);
}

String azaanVoice(SharedPreferences p) {
  final saved = p.getString('azaan_voice');
  if (saved != null && azaanOptions.any((o) => o.id == saved)) return saved;
  return azaanOptions.first.id;
}

Future<void> saveAzaanVoice(SharedPreferences p, String id) async {
  await p.setString('azaan_voice', id);
}

// ---------- setup ----------
Future<void> initReminders() async {
  try {
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_prayer'),
      ),
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();

    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        'prayer_simple',
        'Prayer reminders',
        description: 'A simple notification at prayer time',
        importance: Importance.high,
      ),
    );
    // one channel per azaan, because a channel's sound can't be changed later
    for (final o in azaanOptions) {
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          'ch_${o.id}',
          'Azaan - ${o.name}',
          description: 'Plays the azaan at prayer time',
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound(o.id),
        ),
      );
    }
  } catch (e) {
    debugPrint('Reminder setup failed: $e');
  }
}

NotificationDetails _details(int mode, String voice) {
  final isAzaan = mode == modeAzaan || mode == modeShort;
  return NotificationDetails(
    android: AndroidNotificationDetails(
      isAzaan ? 'ch_$voice' : 'prayer_simple',
      isAzaan ? 'Azaan' : 'Prayer reminders',
      importance: isAzaan ? Importance.max : Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: isAzaan ? RawResourceAndroidNotificationSound(voice) : null,
      // the short azaan: the notification disappears, and the sound stops with it
      timeoutAfter: mode == modeShort ? shortAzaanSeconds * 1000 : null,
    ),
  );
}

Future<void> _schedule(
  int id,
  String title,
  String body,
  DateTime when,
  NotificationDetails details,
) async {
  final date = tz.TZDateTime.from(when, tz.UTC);
  try {
    await _plugin.zonedSchedule(
      id, title, body, date, details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  } catch (_) {
    try {
      await _plugin.zonedSchedule(
        id, title, body, date, details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Could not schedule reminder $id: $e');
    }
  }
}

// ---------- scheduling ----------
// Runs one at a time, so quick taps in settings can't overlap
Future<void> _queue = Future.value();

Future<void> scheduleReminders(SharedPreferences prefs) {
  _queue = _queue.then((_) => _doSchedule(prefs));
  return _queue;
}

Future<void> _doSchedule(SharedPreferences prefs) async {
  try {
    await _plugin.cancelAll();
    final voice = azaanVoice(prefs);
    final now = DateTime.now();

    for (int d = 0; d < 30; d++) {
      final day = DateTime(now.year, now.month, now.day + d);
      final times = timesFor(day);
      final isFriday = day.weekday == DateTime.friday;

      for (int i = 0; i < 5; i++) {
        final isJumma = i == 1 && isFriday;
        final mode = reminderMode(prefs, isJumma ? 5 : i);
        if (mode == modeOff) continue;
        if (!times[i].isAfter(now)) continue;

        final name = isJumma ? 'Jumma' : _names[i];
        await _schedule(
          d * 10 + i,
          name,
          "It's time for $name",
          times[i],
          _details(mode, voice),
        );
      }
    }
  } catch (e) {
    debugPrint('Scheduling reminders failed: $e');
  }
}

// Fires in 5 seconds, so you can hear what it sounds like
Future<void> sendTestReminder(SharedPreferences prefs, int mode) async {
  final title = mode == modeNotification
      ? 'Reminder test'
      : (mode == modeShort ? 'Short azaan test' : 'Full azaan test');
  await _schedule(
    9000 + mode,
    title,
    'This is how it will sound.',
    DateTime.now().add(const Duration(seconds: 5)),
    _details(mode, azaanVoice(prefs)),
  );
}