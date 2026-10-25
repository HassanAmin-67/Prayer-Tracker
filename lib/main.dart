import 'dart:async';
import 'package:adhan_dart/adhan_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prayer_logic.dart';
import 'reminders.dart';

const bgTop = Color(0xFF0B8F58);
const bgBottom = Color(0xFF033A2F);
const mint = Color(0xFF2BD28C);

const userName = 'Hassan';
const greetingLine = 'Assalam O Alaikum,';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
  runApp(const PrayerApp());
}

class PrayerApp extends StatelessWidget {
  const PrayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prayer Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: mint,
        scaffoldBackgroundColor: bgBottom,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const prayers = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];
  static const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  SharedPreferences? prefs;
  late final DateTime today;
  late DateTime selected;
  late DateTime viewMonth;
  Timer? _ticker;

  // one page per month: page 0 is January 2020, the last is December 2060
  static const baseYear = 2020;
  static const totalPages = 12 * 41;
  late PageController pageController;

  int pageFor(DateTime m) => (m.year - baseYear) * 12 + (m.month - 1);
  DateTime monthFor(int page) => DateTime(baseYear + page ~/ 12, page % 12 + 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
        _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    HomeWidget.initiallyLaunchedFromHomeWidget().then(handleWidgetLaunch);
    HomeWidget.widgetClicked.listen(handleWidgetLaunch);
    final now = DateTime.now();
    today = DateTime(now.year, now.month, now.day);
    selected = today;
    viewMonth = DateTime(now.year, now.month);
    pageController = PageController(initialPage: pageFor(viewMonth));
    SharedPreferences.getInstance().then((p) {
      setState(() => prefs = p);
      updateHomeWidget();
      initReminders().then((_) => scheduleReminders(p));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      prefs?.reload().then((_) {
        if (mounted) setState(() {});
        updateHomeWidget();
        final p = prefs;
        if (p != null) scheduleReminders(p);
      });
    }
  }

  // ---------- prayer times ----------
  // Location used for prayer times (Lahore)
  final coordinates = const Coordinates(31.5497, 74.3436);

  // Start time of each of the 5 prayers on a given day
  List<DateTime> timesFor(DateTime d) {
    final params = CalculationMethodParameters.karachi();
    params.madhab = Madhab.hanafi;
    final t = PrayerTimes(
      coordinates: coordinates,
      date: DateTime(d.year, d.month, d.day, 12),
      calculationParameters: params,
      precision: true,
    );
    return [
      t.fajr,
      t.dhuhr,
      t.asr,
      t.maghrib,
      t.isha,
    ].map((x) => x.toLocal()).toList();
  }

  bool isUnlocked(DateTime d, int i) =>
      !DateTime.now().isBefore(timesFor(d)[i]);

  // Sunrise on a given day (Fajr ends at sunrise)
  DateTime sunriseFor(DateTime d) {
    final params = CalculationMethodParameters.karachi();
    params.madhab = Madhab.hanafi;
    final t = PrayerTimes(
      coordinates: coordinates,
      date: DateTime(d.year, d.month, d.day, 12),
      calculationParameters: params,
      precision: true,
    );
    return t.sunrise.toLocal();
  }

  String fmt(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  // ---------- home-screen widget ----------
  // how many prayers whose time has passed are still unticked on day d
  int missedCount(DateTime d) {
    final done = doneFor(d);
    int c = 0;
    for (int i = 0; i < 5; i++) {
      if (isUnlocked(d, i) && !done[i]) c++;
    }
    return c;
  }

  // which day the widget shows
  DateTime widgetDay() {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    if (missedCount(todayDate) > 0) return todayDate;
    for (int back = 1; back <= 7; back++) {
      final d = DateTime(todayDate.year, todayDate.month, todayDate.day - back);
      if (missedCount(d) > 0) return d;
    }
    return todayDate;
  }

  Future<void> updateHomeWidget() async {
    final p = prefs;
    if (p != null) await renderHomeWidget(p);
  }

  // ---------- saved data ----------
  String keyOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<bool> doneFor(DateTime d) {
    final saved = prefs?.getString(keyOf(d));
    if (saved == null || saved.length != 5) return List.filled(5, false);
    return saved.split('').map((c) => c == '1').toList();
  }

  Future<void> toggle(int i) async {
    if (!isUnlocked(selected, i)) return;
    final done = doneFor(selected);
    done[i] = !done[i];
    await prefs?.setString(
      keyOf(selected),
      done.map((b) => b ? '1' : '0').join(),
    );
    setState(() {});
    updateHomeWidget();
  }

    // Opens the day the widget was showing when you tapped it
  void handleWidgetLaunch(Uri? uri) {
    if (uri == null || uri.host != 'open') return;
    final day = parseKey(uri.queryParameters['d'] ?? '');
    if (day == null || !mounted) return;
    setState(() => selected = day);
    goToMonth(DateTime(day.year, day.month));
  }

    void openReminderSettings() {
    final p = prefs;
    if (p == null) return;
    const labels = ['Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Jumma (Friday)'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0A3F33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final voice = azaanVoice(p);
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Reminders',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Notify = simple notification  ·  $shortAzaanSeconds sec = start of the azaan  ·  Full = the whole azaan',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final i in const [0, 1, 5, 2, 3, 4]) ...[
                      Text(labels[i],
                          style: const TextStyle(fontSize: 15, color: Colors.white)),
                      const SizedBox(height: 6),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: [
                          const ButtonSegment(value: modeOff, label: Text('Off')),
                          const ButtonSegment(
                              value: modeNotification, label: Text('Notify')),
                          ButtonSegment(
                              value: modeShort, label: Text('$shortAzaanSeconds sec')),
                          const ButtonSegment(value: modeAzaan, label: Text('Full')),
                        ],
                        selected: {reminderMode(p, i)},
                        onSelectionChanged: (s) async {
                          await saveReminderMode(p, i, s.first);
                          setSheet(() {});
                          scheduleReminders(p);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 4),
                    const Text(
                      'Azaan voice',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    for (final o in azaanOptions)
                      InkWell(
                        onTap: () async {
                          await saveAzaanVoice(p, o.id);
                          setSheet(() {});
                          scheduleReminders(p);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                o.id == voice
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: o.id == voice ? mint : Colors.white54,
                              ),
                              const SizedBox(width: 12),
                              Text(o.name,
                                  style: const TextStyle(
                                      fontSize: 16, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => sendTestReminder(p, modeNotification),
                          child: const Text('Test notify'),
                        ),
                        OutlinedButton(
                          onPressed: () => sendTestReminder(p, modeShort),
                          child: Text('Test $shortAzaanSeconds sec'),
                        ),
                        OutlinedButton(
                          onPressed: () => sendTestReminder(p, modeAzaan),
                          child: const Text('Test full'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void openMonthPicker() {
    int year = viewMonth.year;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A3F33),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => setSheet(() => year--),
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '$year',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setSheet(() => year++),
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (int m = 1; m <= 12; m++)
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            goToMonth(DateTime(year, m));
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color:
                                  (year == viewMonth.year &&
                                      m == viewMonth.month)
                                  ? mint
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              months[m - 1].substring(0, 3),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    (year == viewMonth.year &&
                                        m == viewMonth.month)
                                    ? bgBottom
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() => selected = today);
                      goToMonth(DateTime(today.year, today.month));
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      'Go to today',
                      style: TextStyle(color: mint, fontSize: 15),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

    void changeMonth(int delta) {
    final target = pageFor(viewMonth) + delta;
    if (target < 0 || target >= totalPages) return;
    pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  // jumps straight to a month (used by the month picker and the widget)
  void goToMonth(DateTime m) {
    final p = pageFor(m).clamp(0, totalPages - 1).toInt();
    if (pageController.hasClients) {
      pageController.jumpToPage(p);
    } else {
      pageController.dispose();
      pageController = PageController(initialPage: p);
    }
    setState(() => viewMonth = monthFor(p));
  }

  // ---------- screen ----------
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bgTop, bgBottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                buildHeader(),
                Expanded(flex: 5, child: buildCalendar()),
                Expanded(flex: 5, child: buildPrayers()),
              ],
            ),
          ),
        ),
      ),
    );
  }

    // ---------- header: greeting and next prayer ----------
  Widget buildHeader() {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    // the next prayer: today's, or tomorrow's Fajr after Isha
    String? nextName;
    DateTime? nextTime;
    for (final day in [todayDate, tomorrow]) {
      final times = timesFor(day);
      for (int i = 0; i < 5; i++) {
        if (times[i].isAfter(now)) {
          nextName = (i == 1 && day.weekday == DateTime.friday) ? 'Jumma' : prayers[i];
          nextTime = times[i];
          break;
        }
      }
      if (nextTime != null) break;
    }

    String untilText = '';
    if (nextTime != null) {
      final diff = nextTime.difference(now);
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      untilText = h > 0 ? 'in ${h}h ${m}m' : 'in ${diff.inMinutes < 1 ? 1 : diff.inMinutes} min';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greetingLine,
                  style: TextStyle(
                    fontSize: 13,
                    letterSpacing: 0.3,
                    color: Colors.white.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  userName,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (nextName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Next · $nextName',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    untilText,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: mint,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------- top half: calendar ----------
    Widget buildCalendar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => changeMonth(-1),
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: openMonthPicker,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    '${months[viewMonth.month - 1]} ${viewMonth.year}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => changeMonth(1),
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
          Row(
            children: [
              for (final d in weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 12,
                        color: d == 'Fri'
                            ? mint
                            : Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: PageView.builder(
              controller: pageController,
              itemCount: totalPages,
              onPageChanged: (i) => setState(() => viewMonth = monthFor(i)),
              itemBuilder: (context, i) => buildMonthGrid(monthFor(i)),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildMonthGrid(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1; // Monday first
    final total = DateTime(month.year, month.month + 1, 0).day;
    final rows = ((offset + total) / 7).ceil();

    return Column(
      children: [
        for (int r = 0; r < rows; r++)
          Expanded(
            child: Row(
              children: [
                for (int c = 0; c < 7; c++)
                  Expanded(child: buildCell(month, r * 7 + c - offset + 1, total)),
              ],
            ),
          ),
      ],
    );
  }

    Widget buildCell(DateTime month, int n, int total) {
    if (n < 1 || n > total) return const SizedBox();
    final date = DateTime(month.year, month.month, n);
    final isSel = date == selected;
    final isToday = date == today;
    final done = doneFor(date);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: () => setState(() => selected = date),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSel ? mint : Colors.transparent,
              border: (isToday && !isSel)
                  ? Border.all(color: Colors.white, width: 1.4)
                  : null,
            ),
            child: Text(
              '$n',
              style: TextStyle(
                fontSize: 15,
                fontWeight: (isSel || isToday)
                    ? FontWeight.w700
                    : FontWeight.normal,
                color: isSel ? bgBottom : Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in done)
                Container(
                  width: 4,
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: d ? mint : Colors.white.withValues(alpha: 0.22),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- bottom half: prayers ----------
  Widget buildPrayers() {
    final done = doneFor(selected);
    final isFriday = selected.weekday == DateTime.friday;
    final count = done.where((b) => b).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${weekdayNames[selected.weekday - 1]}, ${selected.day} ${months[selected.month - 1]}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: openReminderSettings,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.notifications_outlined,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$count of 5 prayed',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Column(
              children: [
                for (int i = 0; i < 5; i++)
                  Expanded(child: buildPrayerRow(i, done, isFriday)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPrayerRow(int i, List<bool> done, bool isFriday) {
    final isDone = done[i];
    final prevDone = i > 0 && done[i - 1];
    final isJumma = i == 1 && isFriday;
    final name = isJumma ? 'Jumma' : prayers[i];
    final locked = !isUnlocked(selected, i);
    final startText = fmt(timesFor(selected)[i]);
    final time = i == 0
        ? '$startText  ·  ends at sunrise ${fmt(sunriseFor(selected))}'
        : startText;

    final topLine = i == 0
        ? Colors.transparent
        : (prevDone ? mint : Colors.white.withValues(alpha: 0.2));
    final bottomLine = i == 4
        ? Colors.transparent
        : (isDone ? mint : Colors.white.withValues(alpha: 0.2));

    final circle = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDone
            ? mint
            : (locked
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.transparent),
        border: Border.all(
          color: isDone
              ? mint
              : (locked ? Colors.white.withValues(alpha: 0.25) : Colors.white),
          width: 1.6,
        ),
      ),
      child: isDone
          ? const Icon(Icons.check, size: 18, color: Colors.white)
          : null,
    );

    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: locked ? null : () => toggle(i),
      child: Opacity(
        opacity: locked ? 0.5 : 1,
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Column(
                children: [
                  Expanded(child: Container(width: 2, color: topLine)),
                  circle,
                  Expanded(child: Container(width: 2, color: bottomLine)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: isJumma ? FontWeight.w600 : FontWeight.normal,
                      color: isJumma ? mint : Colors.white,
                    ),
                  ),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (locked)
              Icon(
                Icons.lock_outline,
                size: 20,
                color: Colors.white.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
    );
  }
}
