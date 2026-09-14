import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = HabitStore();
  await store.load();
  runApp(HabitFlowApp(store: store));
}

class Habit {
  final String id;
  String name;
  String emoji;
  Set<int> days; // 1=Mon ... 7=Sun
  Set<String> completions; // yyyy-mm-dd

  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.days,
    required this.completions,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'days': days.toList(),
        'completions': completions.toList(),
      };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: j['name'] ?? 'Habit',
        emoji: j['emoji'] ?? '✨',
        days: Set<int>.from((j['days'] ?? [1,2,3,4,5,6,7]).map((e) => e as int)),
        completions: Set<String>.from((j['completions'] ?? []).map((e) => e.toString())),
      );
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String prettyDate(DateTime d) =>
    '${d.day}/${d.month}/${d.year}';

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class HabitStore extends ChangeNotifier {
  final List<Habit> habits = [];
  String profileName = 'Your Name';
  String? profileImagePath;
  ThemeMode themeMode = ThemeMode.system;
  DateTime joinedDate = DateTime.now();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    profileName = p.getString('profileName') ?? 'Your Name';
    profileImagePath = p.getString('profileImagePath');
    final theme = p.getString('themeMode') ?? 'system';
    themeMode = ThemeMode.values.firstWhere((e) => e.name == theme, orElse: () => ThemeMode.system);
    final joined = p.getString('joinedDate');
    joinedDate = joined == null ? DateTime.now() : DateTime.tryParse(joined) ?? DateTime.now();

    final raw = p.getString('habits');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        habits
          ..clear()
          ..addAll(list.map((e) => Habit.fromJson(Map<String, dynamic>.from(e))));
      } catch (_) {}
    }
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('profileName', profileName);
    if (profileImagePath == null) {
      await p.remove('profileImagePath');
    } else {
      await p.setString('profileImagePath', profileImagePath!);
    }
    await p.setString('themeMode', themeMode.name);
    await p.setString('joinedDate', joinedDate.toIso8601String());
    await p.setString('habits', jsonEncode(habits.map((h) => h.toJson()).toList()));
  }

  Future<void> addHabit(String name, String emoji, Set<int> days) async {
    habits.add(Habit(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      emoji: emoji,
      days: days.isEmpty ? {1,2,3,4,5,6,7} : days,
      completions: {},
    ));
    await save();
    notifyListeners();
  }

  Future<void> deleteHabit(Habit h) async {
    habits.removeWhere((x) => x.id == h.id);
    await save();
    notifyListeners();
  }

  Future<void> toggle(Habit h, DateTime date) async {
    final key = dateKey(date);
    if (h.completions.contains(key)) {
      h.completions.remove(key);
    } else {
      h.completions.add(key);
      HapticFeedback.mediumImpact();
    }
    await save();
    notifyListeners();
  }

  Future<void> setProfileName(String value) async {
    profileName = value.trim().isEmpty ? 'Your Name' : value.trim();
    await save();
    notifyListeners();
  }

  Future<void> setImage(String? path) async {
    profileImagePath = path;
    await save();
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    themeMode = mode;
    await save();
    notifyListeners();
  }

  Future<void> restoreJson(String jsonText) async {
    final data = jsonDecode(jsonText) as Map<String, dynamic>;
    profileName = data['profileName'] ?? profileName;
    final rawHabits = data['habits'] as List? ?? [];
    habits
      ..clear()
      ..addAll(rawHabits.map((e) => Habit.fromJson(Map<String, dynamic>.from(e))));
    await save();
    notifyListeners();
  }

  Map<String, dynamic> backupData() => {
        'app': 'HabitFlow',
        'version': '1.0.0',
        'profileName': profileName,
        'joinedDate': joinedDate.toIso8601String(),
        'habits': habits.map((h) => h.toJson()).toList(),
      };
}

class HabitFlowApp extends StatelessWidget {
  final HabitStore store;
  const HabitFlowApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF7C3AED);
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'HabitFlow',
        themeMode: store.themeMode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light),
          scaffoldBackgroundColor: const Color(0xFFF8F7FC),
          appBarTheme: const AppBarTheme(centerTitle: false),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
          appBarTheme: const AppBarTheme(centerTitle: false),
        ),
        home: HomePage(store: store),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final HabitStore store;
  const HomePage({super.key, required this.store});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(store: widget.store),
      CalendarPage(store: widget.store),
      StatsPage(store: widget.store),
      ProfilePage(store: widget.store),
    ];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      floatingActionButton: tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => showAddHabit(context, widget.store),
              icon: const Icon(Icons.add),
              label: const Text('Add habit'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class TodayPage extends StatelessWidget {
  final HabitStore store;
  const TodayPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final scheduled = store.habits.where((h) => h.days.contains(today.weekday)).toList();
    final upcoming = store.habits.where((h) => !h.days.contains(today.weekday)).toList();

    return AnimatedBuilder(
      animation: store,
      builder: (_, __) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
        children: [
          Text('HabitFlow', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Build your future with today’s habit.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          Text('Today', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (scheduled.isEmpty)
            const EmptyCard(text: 'No habits scheduled today. Add one and start your flow! 🌱')
          else
            ...scheduled.map((h) => HabitCard(habit: h, date: today, store: store)),
          const SizedBox(height: 24),
          Text('Upcoming', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          if (upcoming.isEmpty)
            const EmptyCard(text: 'Nothing upcoming.')
          else
            ...upcoming.map((h) => UpcomingCard(habit: h)),
        ],
      ),
    );
  }
}

class EmptyCard extends StatelessWidget {
  final String text;
  const EmptyCard({super.key, required this.text});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(20), child: Text(text)),
      );
}

class HabitCard extends StatelessWidget {
  final Habit habit;
  final DateTime date;
  final HabitStore store;
  const HabitCard({super.key, required this.habit, required this.date, required this.store});

  @override
  Widget build(BuildContext context) {
    final done = habit.completions.contains(dateKey(date));
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        leading: CircleAvatar(child: Text(habit.emoji, style: const TextStyle(fontSize: 22))),
        title: Text(habit.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${habit.days.length == 7 ? 'Every day' : '${habit.days.length} days/week'}  •  Streak ${streakFor(habit)}'),
        trailing: IconButton(
          tooltip: done ? 'Undo' : 'Complete',
          onPressed: () => store.toggle(habit, date),
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked,
                key: ValueKey(done), size: 32, color: done ? Theme.of(context).colorScheme.primary : null),
          ),
        ),
      ),
    );
  }
}

class UpcomingCard extends StatelessWidget {
  final Habit habit;
  const UpcomingCard({super.key, required this.habit});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Text(habit.emoji, style: const TextStyle(fontSize: 26)),
          title: Text(habit.name),
          subtitle: Text(scheduleLabel(habit.days)),
        ),
      );
}

String scheduleLabel(Set<int> days) {
  const names = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
  return days.length == 7 ? 'Every day' : days.map((d) => names[d - 1]).join(' • ');
}

int streakFor(Habit h) {
  if (h.completions.isEmpty) return 0;
  var cursor = dayOnly(DateTime.now());
  int streak = 0;
  for (int i = 0; i < 370; i++) {
    if (!h.days.contains(cursor.weekday)) {
      cursor = cursor.subtract(const Duration(days: 1));
      continue;
    }
    if (h.completions.contains(dateKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
}

class CalendarPage extends StatefulWidget {
  final HabitStore store;
  const CalendarPage({super.key, required this.store});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Row(
            children: [
              Text('Calendar', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month - 1)), icon: const Icon(Icons.chevron_left)),
              Text('${month.month}/${month.year}', style: const TextStyle(fontWeight: FontWeight.bold)),
              IconButton(onPressed: () => setState(() => month = DateTime(month.year, month.month + 1)), icon: const Icon(Icons.chevron_right)),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: CalendarGrid(store: widget.store, month: month),
            ),
          ),
          const SizedBox(height: 18),
          Text('All habits', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (widget.store.habits.isEmpty) const EmptyCard(text: 'Add a habit to see its calendar.')
          else ...widget.store.habits.map((h) => HabitCalendarSummary(habit: h, month: month)),
        ],
      ),
    );
  }
}

class CalendarGrid extends StatelessWidget {
  final HabitStore store;
  final DateTime month;
  const CalendarGrid({super.key, required this.store, required this.month});

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = List<Widget>.generate(42, (i) {
      final n = i - offset + 1;
      if (n < 1 || n > daysInMonth) return const SizedBox(height: 42);
      final d = DateTime(month.year, month.month, n);
      final scheduled = store.habits.any((h) => h.days.contains(d.weekday));
      final done = store.habits.any((h) => h.days.contains(d.weekday) && h.completions.contains(dateKey(d)));
      return Container(
        height: 42,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: done ? Theme.of(context).colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheduled ? Theme.of(context).colorScheme.outlineVariant : Colors.transparent),
        ),
        alignment: Alignment.center,
        child: Text('$n', style: TextStyle(fontWeight: done ? FontWeight.bold : FontWeight.normal)),
      );
    });
    return Column(
      children: [
        Row(children: ['M','T','W','T','F','S','S'].map((e) => Expanded(child: Center(child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold)))).toList()),
        const SizedBox(height: 8),
        for (int r = 0; r < 6; r++) Row(children: cells.sublist(r * 7, r * 7 + 7).map((w) => Expanded(child: w)).toList()),
      ],
    );
  }
}

class HabitCalendarSummary extends StatelessWidget {
  final Habit habit;
  final DateTime month;
  const HabitCalendarSummary({super.key, required this.habit, required this.month});
  @override
  Widget build(BuildContext context) {
    final count = habit.completions.where((k) {
      final d = DateTime.tryParse(k);
      return d != null && d.year == month.year && d.month == month.month;
    }).length;
    return Card(
      child: ListTile(
        leading: Text(habit.emoji, style: const TextStyle(fontSize: 25)),
        title: Text(habit.name),
        subtitle: Text('$count completion${count == 1 ? '' : 's'} this month • ${scheduleLabel(habit.days)}'),
      ),
    );
  }
}

class StatsPage extends StatelessWidget {
  final HabitStore store;
  const StatsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final totalCompletions = store.habits.fold<int>(0, (a, h) => a + h.completions.length);
    final current = store.habits.isEmpty ? 0 : store.habits.map(streakFor).reduce((a,b) => a+b);
    final scheduled = _scheduledOccurrences(store, 365);
    final completed = totalCompletions;
    final rate = scheduled == 0 ? 0 : ((completed.clamp(0, scheduled) / scheduled) * 100).round();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        Text('Your progress', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: [
            StatCard(label: 'Total habits', value: '${store.habits.length}', icon: Icons.list_alt),
            StatCard(label: 'Completions', value: '$totalCompletions', icon: Icons.check_circle_outline),
            StatCard(label: 'Current streak', value: '$current', icon: Icons.local_fire_department),
            StatCard(label: 'Completion rate', value: '$rate%', icon: Icons.percent),
          ],
        ),
        const SizedBox(height: 22),
        Text('Achievements', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Achievement(title: 'First step', unlocked: totalCompletions >= 1, text: 'Complete your first habit.'),
        Achievement(title: '7-day flow', unlocked: store.habits.any((h) => streakFor(h) >= 7), text: 'Reach a 7-day streak.'),
        Achievement(title: 'Consistency', unlocked: totalCompletions >= 30, text: 'Complete 30 habits.'),
        Achievement(title: 'Habit builder', unlocked: store.habits.length >= 5, text: 'Create 5 habits.'),
      ],
    );
  }

  int _scheduledOccurrences(HabitStore store, int daysBack) {
    final start = DateTime.now().subtract(Duration(days: daysBack - 1));
    int count = 0;
    for (int i = 0; i < daysBack; i++) {
      final d = start.add(Duration(days: i));
      count += store.habits.where((h) => h.days.contains(d.weekday)).length;
    }
    return count;
  }
}

class StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const StatCard({super.key, required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon),
            const Spacer(),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(label),
          ]),
        ),
      );
}

class Achievement extends StatelessWidget {
  final String title, text;
  final bool unlocked;
  const Achievement({super.key, required this.title, required this.text, required this.unlocked});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(unlocked ? Icons.emoji_events : Icons.lock_outline)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(text),
          trailing: Text(unlocked ? 'Unlocked' : 'Locked'),
        ),
      );
}

class ProfilePage extends StatefulWidget {
  final HabitStore store;
  const ProfilePage({super.key, required this.store});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final picker = ImagePicker();

  Future<void> editName() async {
    final controller = TextEditingController(text: widget.store.profileName);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit profile name'),
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () { widget.store.setProfileName(controller.text); Navigator.pop(context); }, child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> pickImage() async {
    final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x != null) await widget.store.setImage(x.path);
  }

  Future<void> exportCsv() async {
    final rows = <List<dynamic>>[
      ['Habit', 'Schedule', 'Completion Count', 'Current Streak'],
      ...widget.store.habits.map((h) => [h.name, scheduleLabel(h.days), h.completions.length, streakFor(h)]),
    ];
    final csvText = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/habitflow_stats.csv');
    await file.writeAsString(csvText);
    await Share.shareXFiles([XFile(file.path)], text: 'HabitFlow statistics');
  }

  Future<void> backup() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/habitflow_backup.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(widget.store.backupData()));
    await Share.shareXFiles([XFile(file.path)], text: 'HabitFlow backup');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (_, __) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
        children: [
          Text('Profile', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                GestureDetector(
                  onTap: pickImage,
                  child: CircleAvatar(
                    radius: 36,
                    backgroundImage: widget.store.profileImagePath != null
                        ? FileImage(File(widget.store.profileImagePath!))
                        : null,
                    child: widget.store.profileImagePath == null ? const Icon(Icons.person, size: 36) : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.store.profileName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Joined ${prettyDate(widget.store.joinedDate)}'),
                ])),
                IconButton(onPressed: editName, icon: const Icon(Icons.edit)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          _profileStat(context, 'Total habits', '${widget.store.habits.length}', Icons.list_alt),
          _profileStat(context, 'Total completions', '${widget.store.habits.fold<int>(0, (a,h) => a + h.completions.length)}', Icons.check),
          _profileStat(context, 'Overall current streak', '${widget.store.habits.fold<int>(0, (a,h) => a + streakFor(h))}', Icons.local_fire_department),
          _profileStat(context, 'Best streak', '${widget.store.habits.isEmpty ? 0 : widget.store.habits.map(_bestStreak).reduce((a,b) => a>b?a:b)}', Icons.emoji_events),
          _profileStat(context, 'Completion rate', '${_completionRate(widget.store)}%', Icons.percent),
          const SizedBox(height: 14),
          Card(
            child: Column(children: [
              const ListTile(title: Text('Appearance'), subtitle: Text('Light, dark, or follow system')),
              RadioListTile<ThemeMode>(value: ThemeMode.system, groupValue: widget.store.themeMode, onChanged: (v) => widget.store.setTheme(v!), title: const Text('System')),
              RadioListTile<ThemeMode>(value: ThemeMode.light, groupValue: widget.store.themeMode, onChanged: (v) => widget.store.setTheme(v!), title: const Text('Light')),
              RadioListTile<ThemeMode>(value: ThemeMode.dark, groupValue: widget.store.themeMode, onChanged: (v) => widget.store.setTheme(v!), title: const Text('Dark')),
            ]),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(children: [
              ListTile(leading: const Icon(Icons.table_view), title: const Text('Export CSV'), subtitle: const Text('Share your habit statistics'), onTap: exportCsv),
              ListTile(leading: const Icon(Icons.backup_outlined), title: const Text('Backup JSON'), subtitle: const Text('Create a portable backup'), onTap: backup),
              const ListTile(leading: Icon(Icons.notifications_none), title: Text('Reminders'), subtitle: Text('One reminder per habit — coming in the next release')),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _profileStat(BuildContext c, String label, String value, IconData icon) => Card(
        child: ListTile(leading: Icon(icon), title: Text(label), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold))),
      );

  int _bestStreak(Habit h) {
    if (h.completions.isEmpty) return 0;
    final dates = h.completions.map(DateTime.parse).toList()..sort();
    int best = 1, cur = 1;
    for (int i = 1; i < dates.length; i++) {
      final diff = dates[i].difference(dates[i-1]).inDays;
      if (diff == 1) { cur++; best = best > cur ? best : cur; } else { cur = 1; }
    }
    return best;
  }

  int _completionRate(HabitStore s) {
    int scheduled = 0;
    final start = DateTime.now().subtract(const Duration(days: 364));
    for (int i = 0; i < 365; i++) {
      final d = start.add(Duration(days: i));
      scheduled += s.habits.where((h) => h.days.contains(d.weekday)).length;
    }
    if (scheduled == 0) return 0;
    final completed = s.habits.fold<int>(0, (a,h) => a + h.completions.length);
    return ((completed.clamp(0, scheduled) / scheduled) * 100).round();
  }
}

Future<void> showAddHabit(BuildContext context, HabitStore store) async {
  final name = TextEditingController();
  final emoji = TextEditingController(text: '✨');
  final selected = <int>{1,2,3,4,5,6,7};
  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('New habit'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Habit name', hintText: 'Read 20 minutes')),
            TextField(controller: emoji, decoration: const InputDecoration(labelText: 'Emoji')),
            const SizedBox(height: 16),
            const Text('Schedule', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: List.generate(7, (i) {
                final d = i + 1;
                const labels = ['M','T','W','T','F','S','S'];
                return FilterChip(label: Text(labels[i]), selected: selected.contains(d), onSelected: (v) => setState(() => v ? selected.add(d) : selected.remove(d)));
              }),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              store.addHabit(name.text.trim(), emoji.text.trim().isEmpty ? '✨' : emoji.text.trim(), selected);
              Navigator.pop(context);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}
