import 'dart:ui';

import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_card.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthsShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

// Location used for prayer times (Lahore)
const _coordinates = Coordinates(31.5497, 74.3436);

String keyOf(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseKey(String s) {
  final p = s.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]);
  final m = int.tryParse(p[1]);
  final d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

List<bool> doneFor(SharedPreferences prefs, DateTime d) {
  final saved = prefs.getString(keyOf(d));
  if (saved == null || saved.length != 5) return List.filled(5, false);
  return saved.split('').map((c) => c == '1').toList();
}

List<DateTime> timesFor(DateTime d) {
  final params = CalculationMethodParameters.karachi();
  params.madhab = Madhab.hanafi;
  final t = PrayerTimes(
    coordinates: _coordinates,
    date: DateTime(d.year, d.month, d.day, 12),
    calculationParameters: params,
    precision: true,
  );
  return [t.fajr, t.dhuhr, t.asr, t.maghrib, t.isha]
      .map((x) => x.toLocal())
      .toList();
}

bool isUnlocked(DateTime d, int i) => !DateTime.now().isBefore(timesFor(d)[i]);

int missedCount(SharedPreferences prefs, DateTime d) {
  final done = doneFor(prefs, d);
  int c = 0;
  for (int i = 0; i < 5; i++) {
    if (isUnlocked(d, i) && !done[i]) c++;
  }
  return c;
}

// Which day the widget shows
DateTime widgetDay(SharedPreferences prefs) {
  final now = DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);
  if (missedCount(prefs, todayDate) > 0) return todayDate;
  for (int back = 1; back <= 7; back++) {
    final d = DateTime(todayDate.year, todayDate.month, todayDate.day - back);
    if (missedCount(prefs, d) > 0) return d;
  }
  return todayDate;
}

// Widget taps only tick, they never untick
Future<void> markDone(SharedPreferences prefs, DateTime day, int i) async {
  if (!isUnlocked(day, i)) return;
  final done = doneFor(prefs, day);
  if (done[i]) return;
  done[i] = true;
  await prefs.setString(keyOf(day), done.map((b) => b ? '1' : '0').join());
}

Future<void> renderHomeWidget(SharedPreferences prefs) async {
  try {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final day = widgetDay(prefs);
    final done = doneFor(prefs, day);
    final isFri = day.weekday == DateTime.friday;

    final states = List<DotState>.generate(5, (i) {
      if (done[i]) return DotState.done;
      if (isUnlocked(day, i)) return DotState.missed;
      return DotState.locked;
    });
    final names = ['Fajr', isFri ? 'Jumma' : 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
    final label = day == todayDate
        ? 'TODAY'
        : '${_weekdays[day.weekday - 1]} ${day.day} ${_monthsShort[day.month - 1]} · CATCH UP'
            .toUpperCase();

    // tells the Android side which day the taps belong to
    await HomeWidget.saveWidgetData<String>('widget_day', keyOf(day));
    // moments when the widget must be redrawn: each prayer time and midnight
    final redrawAt = <int>[];
    for (int d = 0; d < 3; d++) {
      final dd = DateTime(now.year, now.month, now.day + d);
      for (final t in timesFor(dd)) {
        redrawAt.add(t.add(const Duration(seconds: 3)).millisecondsSinceEpoch);
      }
      redrawAt.add(
        DateTime(now.year, now.month, now.day + d + 1, 0, 0, 5).millisecondsSinceEpoch,
      );
    }
    redrawAt.removeWhere((t) => t <= now.millisecondsSinceEpoch);
    await HomeWidget.saveWidgetData<String>('refresh_times', redrawAt.join(','));    
    await HomeWidget.renderFlutterWidget(
      PrayerWidgetCard(
        label: label,
        doneCount: done.where((b) => b).length,
        names: names,
        states: states,
      ),
      key: 'prayer_widget_image',
      logicalSize: const Size(320, 110),
      pixelRatio: 3,
    );
    await HomeWidget.updateWidget(
      qualifiedAndroidName: 'com.example.prayer_tracker.PrayerWidgetProvider',
    );
  } catch (e) {
    debugPrint('Widget update failed: $e');
  }
}

// Runs in the background when you tap a circle, or when a redraw alarm fires
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  if (uri == null) return;

  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // a prayer time arrived: just redraw the widget
  if (uri.host == 'refresh') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await renderHomeWidget(prefs);
    return;
  }

  // a circle was tapped: tick that prayer
  if (uri.host != 'tick') return;
  final i = int.tryParse(uri.queryParameters['i'] ?? '');
  final day = parseKey(uri.queryParameters['d'] ?? '');
  if (i == null || i < 0 || i > 4 || day == null) return;

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await markDone(prefs, day, i);
  await renderHomeWidget(prefs);
}