import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyWeekApp());
}

const List<String> kDayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const List<int> kPalette = [
  0xFF7C9CFF,
  0xFF66BB6A,
  0xFFFFB74D,
  0xFFE57373,
  0xFFBA68C8,
  0xFF4DD0E1,
  0xFFA1887F,
  0xFFF06292,
];

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

DateTime _mondayOf(DateTime d) {
  final date = DateTime(d.year, d.month, d.day);
  return date.subtract(Duration(days: date.weekday - 1));
}

String _weekKey(DateTime monday) {
  final y = monday.year.toString().padLeft(4, '0');
  final m = monday.month.toString().padLeft(2, '0');
  final d = monday.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _currentWeekKey() => _weekKey(_mondayOf(DateTime.now()));

class Category {
  final String id;
  String name;
  int color;
  Category({required this.id, required this.name, required this.color});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        color: j['color'] as int,
      );
}

class Task {
  final String id;
  String title;
  int day; // 0 = Monday ... 6 = Sunday
  String? time; // 'HH:mm' or null
  String categoryId;
  bool done;
  String weekStart; // 'yyyy-MM-dd' Monday of this task's week
  String? sourceId; // original task id when carried forward

  Task({
    required this.id,
    required this.title,
    required this.day,
    this.time,
    required this.categoryId,
    this.done = false,
    required this.weekStart,
    this.sourceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'day': day,
        'time': time,
        'categoryId': categoryId,
        'done': done,
        'weekStart': weekStart,
        'sourceId': sourceId,
      };

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] as String,
        title: j['title'] as String,
        day: j['day'] as int,
        time: j['time'] as String?,
        categoryId: j['categoryId'] as String,
        done: (j['done'] as bool?) ?? false,
        weekStart: (j['weekStart'] as String?) ?? '',
        sourceId: j['sourceId'] as String?,
      );
}

class MyWeekApp extends StatelessWidget {
  const MyWeekApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C9CFF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'My Week',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF101114),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF101114),
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Category> _categories = [];
  List<Task> _tasks = [];
  bool _loading = true;
  String _currentWeek = _currentWeekKey();
  String _viewWeek = _currentWeekKey(); // week currently being viewed
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refreshWeek());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshWeek();
  }

  void _refreshWeek() {
    final w = _currentWeekKey();
    if (w != _currentWeek) {
      setState(() {
        _currentWeek = w;
        _viewWeek = w;
      });
      _pruneOld();
      _save();
    }
  }

  String _prevWeekKey() =>
      _weekKey(DateTime.parse(_currentWeek).subtract(const Duration(days: 7)));

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _currentWeek = _currentWeekKey();
    _viewWeek = _currentWeek;
    final catStr = prefs.getString('categories');
    final taskStr = prefs.getString('tasks');

    if (catStr != null) {
      final List<dynamic> raw = jsonDecode(catStr) as List<dynamic>;
      _categories =
          raw.map((e) => Category.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      _categories = [
        Category(id: 'work_default', name: 'Work', color: kPalette[0]),
        Category(id: 'leisure_default', name: 'Leisure', color: kPalette[1]),
      ];
    }

    if (taskStr != null) {
      final List<dynamic> raw = jsonDecode(taskStr) as List<dynamic>;
      _tasks = raw.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
      for (final t in _tasks) {
        if (t.weekStart.isEmpty) t.weekStart = _currentWeek;
      }
    }

    _pruneOld();
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'categories', jsonEncode(_categories.map((e) => e.toJson()).toList()));
    await prefs.setString(
        'tasks', jsonEncode(_tasks.map((e) => e.toJson()).toList()));
  }

  // Keep only the current week and the immediately previous week.
  void _pruneOld() {
    final prev = _prevWeekKey();
    _tasks.removeWhere((t) => t.weekStart.compareTo(prev) < 0);
  }

  Category? _catById(String id) {
    for (final c in _categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Task> _tasksForDay(int day) {
    final list = _tasks
        .where((t) => t.weekStart == _viewWeek && t.day == day)
        .toList();
    list.sort((a, b) {
      final at = a.time, bt = b.time;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    return list;
  }

  String _weekRangeLabel() {
    final mon = DateTime.parse(_viewWeek);
    final sun = mon.add(const Duration(days: 6));
    return '${mon.day} ${kMonths[mon.month - 1]} – ${sun.day} ${kMonths[sun.month - 1]}';
  }

  // Unfinished tasks from last week that haven't been carried in yet.
  List<Task> _pendingCarry() {
    final prev = _prevWeekKey();
    final carried = _tasks
        .where((t) => t.weekStart == _currentWeek && t.sourceId != null)
        .map((t) => t.sourceId)
        .toSet();
    return _tasks
        .where((t) =>
            t.weekStart == prev && !t.done && !carried.contains(t.id))
        .toList();
  }

  void _carryForward() {
    final pending = _pendingCarry();
    if (pending.isEmpty) return;
    setState(() {
      for (final t in pending) {
        _tasks.add(Task(
          id: _newId(),
          title: t.title,
          day: t.day,
          time: t.time,
          categoryId: t.categoryId,
          done: false,
          weekStart: _currentWeek,
          sourceId: t.id,
        ));
      }
    });
    _save();
  }

  Future<Category?> _showAddCategoryDialog() async {
    final controller = TextEditingController();
    int selectedColor = kPalette[_categories.length % kPalette.length];

    final result = await showDialog<Category>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1C20),
              title: const Text('New category'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final color in kPalette)
                        GestureDetector(
                          onTap: () => setDlg(() => selectedColor = color),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selectedColor == color
                                    ? Colors.white
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = controller.text.trim();
                    if (name.isEmpty) return;
                    Navigator.of(ctx).pop(
                      Category(id: _newId(), name: name, color: selectedColor),
                    );
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() => _categories.add(result));
      await _save();
    }
    return result;
  }

  void _openTaskEditor({Task? existing, int? presetDay}) {
    final titleController = TextEditingController(text: existing?.title ?? '');
    int selectedDay = existing?.day ?? presetDay ?? 0;
    String? selectedCategoryId = existing?.categoryId ??
        (_categories.isNotEmpty ? _categories.first.id : null);
    String? selectedTime = existing?.time;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1C20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    existing == null ? 'New task' : 'Edit task',
                    style: Theme.of(ctx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    autofocus: existing == null,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Task',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (int i = 0; i < kDayNames.length; i++)
                        DropdownMenuItem(value: i, child: Text(kDayNames[i])),
                    ],
                    onChanged: (v) =>
                        setSheet(() => selectedDay = v ?? selectedDay),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedCategoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final c in _categories)
                        DropdownMenuItem(
                          value: c.id,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Color(c.color),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(c.name),
                            ],
                          ),
                        ),
                      const DropdownMenuItem(
                        value: '__add__',
                        child: Text('+ New category…'),
                      ),
                    ],
                    onChanged: (v) async {
                      if (v == '__add__') {
                        final created = await _showAddCategoryDialog();
                        if (created != null) {
                          setSheet(() => selectedCategoryId = created.id);
                        }
                      } else {
                        setSheet(() => selectedCategoryId = v);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(
                            selectedTime == null
                                ? 'Add time (optional)'
                                : selectedTime!,
                          ),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime: TimeOfDay.now(),
                            );
                            if (picked != null) {
                              final h = picked.hour.toString().padLeft(2, '0');
                              final m =
                                  picked.minute.toString().padLeft(2, '0');
                              setSheet(() => selectedTime = '$h:$m');
                            }
                          },
                        ),
                      ),
                      if (selectedTime != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setSheet(() => selectedTime = null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        final title = titleController.text.trim();
                        if (title.isEmpty ||
                            selectedCategoryId == null ||
                            selectedCategoryId == '__add__') {
                          return;
                        }
                        setState(() {
                          if (existing == null) {
                            _tasks.add(Task(
                              id: _newId(),
                              title: title,
                              day: selectedDay,
                              time: selectedTime,
                              categoryId: selectedCategoryId!,
                              weekStart: _viewWeek,
                            ));
                          } else {
                            existing.title = title;
                            existing.day = selectedDay;
                            existing.time = selectedTime;
                            existing.categoryId = selectedCategoryId!;
                          }
                        });
                        _save();
                        Navigator.of(ctx).pop();
                      },
                      child: Text(existing == null ? 'Add task' : 'Save'),
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final carryCount = _pendingCarry().length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Week'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: _buildWeekNav(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.label_outline),
            tooltip: 'Categories',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => CategoriesScreen(
                  categories: _categories,
                  tasks: _tasks,
                  onAdd: _showAddCategoryDialog,
                  onDelete: (c) {
                    setState(() => _categories.remove(c));
                    _save();
                  },
                ),
              ));
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTaskEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Task'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          if (carryCount > 0 && _viewWeek == _currentWeek)
            _buildCarryBanner(carryCount),
          for (int day = 0; day < kDayNames.length; day++)
            _buildDaySection(day),
        ],
      ),
    );
  }

  Widget _buildWeekNav() {
    final prev = _prevWeekKey();
    final isCurrent = _viewWeek == _currentWeek;
    final canBack = isCurrent; // step back to last week
    final canForward = _viewWeek == prev; // return to this week
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            color: canBack ? Colors.white : Colors.white24,
            tooltip: 'Last week',
            onPressed: canBack ? () => setState(() => _viewWeek = prev) : null,
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCurrent ? 'This week' : 'Last week',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? const Color(0xFF7C9CFF) : Colors.white,
                  ),
                ),
                Text(
                  _weekRangeLabel(),
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            color: canForward ? Colors.white : Colors.white24,
            tooltip: 'This week',
            onPressed: canForward
                ? () => setState(() => _viewWeek = _currentWeek)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildCarryBanner(int n) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2536),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x557C9CFF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, color: Color(0xFF7C9CFF), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$n unfinished task${n == 1 ? '' : 's'} from last week',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          TextButton(onPressed: _carryForward, child: const Text('Bring in')),
        ],
      ),
    );
  }

  Widget _buildDaySection(int day) {
    final dayTasks = _tasksForDay(day);
    final weekend = day >= 5;
    return DragTarget<Task>(
      onWillAcceptWithDetails: (d) => d.data.day != day,
      onAcceptWithDetails: (d) {
        setState(() => d.data.day = day);
        _save();
      },
      builder: (context, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: highlight ? const Color(0x227C9CFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: highlight
                ? Border.all(color: const Color(0xFF7C9CFF))
                : Border.all(color: Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                child: Row(
                  children: [
                    Text(
                      kDayNames[day].toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: weekend
                            ? const Color(0xFF7C9CFF)
                            : Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (dayTasks.isNotEmpty)
                      Text(
                        '${dayTasks.length}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white38),
                      ),
                  ],
                ),
              ),
              if (dayTasks.isEmpty)
                Container(
                  height: 36,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    highlight ? 'Drop here' : '—',
                    style: TextStyle(
                      color: highlight ? const Color(0xFF7C9CFF) : Colors.white24,
                    ),
                  ),
                )
              else
                for (final t in dayTasks) _buildTaskTile(t),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTaskTile(Task t) {
    final cat = _catById(t.categoryId);
    final catColor = cat != null ? Color(cat.color) : Colors.grey;

    final tile = Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1C20),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Checkbox(
            value: t.done,
            onChanged: (v) {
              setState(() => t.done = v ?? false);
              _save();
            },
          ),
          Expanded(
            child: InkWell(
              onTap: () => _openTaskEditor(existing: t),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.title,
                      style: TextStyle(
                        decoration:
                            t.done ? TextDecoration.lineThrough : null,
                        color: t.done ? Colors.white38 : Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: catColor.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            cat?.name ?? 'Uncategorized',
                            style: TextStyle(fontSize: 12, color: catColor),
                          ),
                        ),
                        if (t.time != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            t.time!,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white38),
            onPressed: () {
              setState(() => _tasks.remove(t));
              _save();
            },
          ),
        ],
      ),
    );

    return LongPressDraggable<Task>(
      data: t,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF23262C),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 12),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.drag_indicator, color: catColor, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }
}

class CategoriesScreen extends StatefulWidget {
  final List<Category> categories;
  final List<Task> tasks;
  final Future<Category?> Function() onAdd;
  final void Function(Category) onDelete;

  const CategoriesScreen({
    super.key,
    required this.categories,
    required this.tasks,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await widget.onAdd();
          if (mounted) setState(() {});
        },
        child: const Icon(Icons.add),
      ),
      body: ListView(
        children: [
          if (widget.categories.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No categories yet. Tap + to add one.',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          for (final c in widget.categories)
            ListTile(
              leading: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Color(c.color),
                  shape: BoxShape.circle,
                ),
              ),
              title: Text(c.name),
              subtitle: Text(
                '${widget.tasks.where((t) => t.categoryId == c.id).length} task(s)',
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  final used =
                      widget.tasks.any((t) => t.categoryId == c.id);
                  if (used) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Remove its tasks first, then delete this category.'),
                      ),
                    );
                    return;
                  }
                  widget.onDelete(c);
                  setState(() {});
                },
              ),
            ),
        ],
      ),
    );
  }
}
