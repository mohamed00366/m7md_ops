// =============================================================================
// ✅ My Tasks Tab — قائِمة مَهامّ شَخصِيّة (To-Do)
// =============================================================================
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/events_tasks_service.dart';
import '../../core/theme/app_colors.dart';

class MyTasksTab extends StatefulWidget {
  const MyTasksTab({super.key});

  @override
  State<MyTasksTab> createState() => _MyTasksTabState();
}

class _MyTasksTabState extends State<MyTasksTab> {
  bool _loading = true;
  List<UserTask> _tasks = [];
  bool _showDone = false;
  TaskPriority? _priorityFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final id = auth.currentUser?.id;
    if (id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _tasks = await EventsTasksService.instance.listMyTasks(
      accountId: id,
      includeDone: _showDone,
    );
    if (mounted) setState(() => _loading = false);
  }

  List<UserTask> get _filtered {
    var list = _tasks;
    if (_priorityFilter != null) {
      list = list.where((t) => t.priority == _priorityFilter).toList();
    }
    return list;
  }

  // ============================================================
  // KPIs
  // ============================================================
  ({int total, int overdue, int dueToday, int done}) _kpis() {
    int overdue = 0, dueToday = 0, done = 0;
    for (final t in _tasks) {
      if (t.isOverdue) overdue++;
      if (t.isDueToday) dueToday++;
      if (t.status == TaskStatus.done) done++;
    }
    return (
      total: _tasks.length,
      overdue: overdue,
      dueToday: dueToday,
      done: done
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final k = _kpis();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  _kpiBar(k, isAr),
                  _filterBar(isAr),
                  Expanded(
                    child: _filtered.isEmpty
                        ? _empty(isAr)
                        : ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(12, 4, 12, 96),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) =>
                                _taskCard(_filtered[i], isAr),
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_task),
        label: Text(isAr ? 'مَهَمَّة جَديدة' : 'New Task'),
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _kpiBar(({int total, int overdue, int dueToday, int done}) k,
      bool isAr) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _miniKpi(isAr ? 'الإجمالي' : 'Total', k.total,
              AppColors.brand, Icons.list_alt),
          const SizedBox(width: 4),
          _miniKpi(isAr ? 'اليَوم' : 'Today', k.dueToday,
              AppColors.warning, Icons.today),
          const SizedBox(width: 4),
          _miniKpi(isAr ? 'مُتَأَخِّرة' : 'Overdue', k.overdue,
              AppColors.danger, Icons.warning_amber),
          const SizedBox(width: 4),
          _miniKpi(isAr ? 'مُنجَزة' : 'Done', k.done,
              AppColors.success, Icons.check_circle),
        ],
      ),
    );
  }

  Widget _miniKpi(String label, int value, Color c, IconData i) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(i, color: c, size: 16),
            const SizedBox(height: 2),
            Text('$value',
                style: TextStyle(
                    color: c,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
            Text(label,
                style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _filterBar(bool isAr) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Priority filter
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _prioChip(null, isAr ? 'الكُلّ' : 'All'),
                  ...TaskPriority.values
                      .map((p) => _prioChip(p, p.labelAr())),
                ],
              ),
            ),
          ),
          // Show done toggle
          Row(children: [
            Text(isAr ? 'المُنجَزة' : 'Done',
                style: const TextStyle(fontSize: 11)),
            Switch(
              value: _showDone,
              onChanged: (v) {
                setState(() => _showDone = v);
                _load();
              },
            ),
          ]),
        ],
      ),
    );
  }

  Widget _prioChip(TaskPriority? p, String label) {
    final selected = _priorityFilter == p;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 10)),
        selected: selected,
        onSelected: (_) => setState(() => _priorityFilter = p),
      ),
    );
  }

  Widget _empty(bool isAr) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.task_alt, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            isAr ? '✨ لا تُوجَد مَهامّ' : '✨ No tasks',
            style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            isAr
                ? 'أَضِف مَهَمَّة جَديدة بِالضَغط أَدناه'
                : 'Add a new task using the button below',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(UserTask t, bool isAr) {
    final isDone = t.status == TaskStatus.done;
    final isCancelled = t.status == TaskStatus.cancelled;
    final color = _priorityColor(t.priority);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: isDone
          ? Colors.green.withOpacity(0.05)
          : t.isOverdue
              ? AppColors.danger.withOpacity(0.05)
              : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openEditor(existing: t),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Checkbox-like toggle for status
              GestureDetector(
                onTap: () async {
                  final newStatus =
                      isDone ? TaskStatus.todo : TaskStatus.done;
                  await EventsTasksService.instance
                      .updateTaskStatus(t.id, newStatus);
                  _load();
                },
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isDone ? AppColors.success : color,
                        width: 2),
                    color: isDone
                        ? AppColors.success
                        : Colors.transparent,
                  ),
                  child: isDone
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 14)
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                        color: isCancelled ? Colors.grey : null,
                      ),
                    ),
                    if (t.description != null && t.description!.isNotEmpty)
                      Text(t.description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 4, runSpacing: 4, children: [
                      _chip(t.priority.labelAr(), color),
                      _chip(t.status.labelAr(), _statusColor(t.status)),
                      if (t.dueDate != null)
                        _chip(
                          '📅 ${t.dueDate!.toIso8601String().substring(0, 10)}',
                          t.isOverdue
                              ? AppColors.danger
                              : t.isDueToday
                                  ? AppColors.warning
                                  : Colors.grey.shade700,
                        ),
                    ]),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.danger),
                onPressed: () => _confirmDelete(t, isAr),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _priorityColor(TaskPriority p) {
    switch (p) {
      case TaskPriority.low:
        return AppColors.success;
      case TaskPriority.normal:
        return AppColors.brand;
      case TaskPriority.high:
        return AppColors.warning;
      case TaskPriority.urgent:
        return AppColors.danger;
    }
  }

  Color _statusColor(TaskStatus s) {
    switch (s) {
      case TaskStatus.todo:
        return Colors.grey.shade700;
      case TaskStatus.inProgress:
        return AppColors.warning;
      case TaskStatus.done:
        return AppColors.success;
      case TaskStatus.cancelled:
        return Colors.grey;
    }
  }

  Widget _chip(String label, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: c, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }

  Future<void> _confirmDelete(UserTask t, bool isAr) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'حَذف المَهَمَّة؟' : 'Delete task?'),
        content: Text('"${t.title}"'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(isAr ? 'إلغاء' : 'Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(isAr ? 'حَذف' : 'Delete')),
        ],
      ),
    );
    if (ok == true) {
      await EventsTasksService.instance.deleteTask(t.id);
      _load();
    }
  }

  Future<void> _openEditor({UserTask? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TaskEditor(existing: existing),
    );
    if (result == true) _load();
  }
}

// ============================================================
// Task Editor Sheet
// ============================================================
class _TaskEditor extends StatefulWidget {
  final UserTask? existing;
  const _TaskEditor({this.existing});

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late TextEditingController _title;
  late TextEditingController _desc;
  TaskPriority _priority = TaskPriority.normal;
  TaskStatus _status = TaskStatus.todo;
  DateTime? _dueDate;
  TimeOfDay? _dueTime;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _title = TextEditingController(text: t?.title ?? '');
    _desc = TextEditingController(text: t?.description ?? '');
    if (t != null) {
      _priority = t.priority;
      _status = t.status;
      _dueDate = t.dueDate;
      if (t.dueDate != null) {
        _dueTime = TimeOfDay(
            hour: t.dueDate!.hour, minute: t.dueDate!.minute);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.read<AuthProvider>();
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.existing == null
                  ? (isAr ? '➕ مَهَمَّة جَديدة' : '➕ New Task')
                  : (isAr ? '✏️ تَعديل مَهَمَّة' : '✏️ Edit Task'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: isAr ? 'العُنوان *' : 'Title *',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _desc,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: isAr ? 'الوَصف' : 'Description',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<TaskPriority>(
              value: _priority,
              decoration: InputDecoration(
                labelText: isAr ? 'الأَولَوِيّة' : 'Priority',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              items: TaskPriority.values
                  .map((p) => DropdownMenuItem(
                      value: p, child: Text(p.labelAr())))
                  .toList(),
              onChanged: (v) => setState(() => _priority = v ?? _priority),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<TaskStatus>(
              value: _status,
              decoration: InputDecoration(
                labelText: isAr ? 'الحالة' : 'Status',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              items: TaskStatus.values
                  .map((s) => DropdownMenuItem(
                      value: s, child: Text(s.labelAr())))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    _dueDate == null
                        ? (isAr ? 'بِدون تاريخ' : 'No due date')
                        : _dueDate!.toIso8601String().substring(0, 10),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dueDate ?? DateTime.now(),
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 30)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 730)),
                    );
                    if (picked != null) setState(() => _dueDate = picked);
                  },
                ),
              ),
              if (_dueDate != null) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time, size: 16),
                    label: Text(
                      _dueTime == null
                          ? (isAr ? 'الوَقت' : 'Time')
                          : '${_dueTime!.hour.toString().padLeft(2, '0')}:${_dueTime!.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _dueTime ??
                            const TimeOfDay(hour: 17, minute: 0),
                      );
                      if (t != null) setState(() => _dueTime = t);
                    },
                  ),
                ),
              ],
              if (_dueDate != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() {
                    _dueDate = null;
                    _dueTime = null;
                  }),
                ),
            ]),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: Text(isAr ? 'حِفظ' : 'Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                if (_title.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.danger,
                    content:
                        Text(isAr ? 'العُنوان مَطلوب' : 'Title required'),
                  ));
                  return;
                }
                final id = auth.currentUser?.id;
                if (id == null) return;

                DateTime? finalDue = _dueDate;
                if (_dueDate != null && _dueTime != null) {
                  finalDue = DateTime(
                    _dueDate!.year,
                    _dueDate!.month,
                    _dueDate!.day,
                    _dueTime!.hour,
                    _dueTime!.minute,
                  );
                }

                final svc = EventsTasksService.instance;
                final task = UserTask(
                  id: widget.existing?.id ?? '',
                  accountId: id,
                  title: _title.text.trim(),
                  description: _desc.text.trim().isEmpty
                      ? null
                      : _desc.text.trim(),
                  priority: _priority,
                  status: _status,
                  dueDate: finalDue,
                );
                bool ok;
                if (widget.existing == null) {
                  ok = (await svc.createTask(task)) != null;
                } else {
                  final updates = {
                    'title': task.title,
                    if (task.description != null)
                      'description': task.description,
                    'priority': task.priority.key,
                    'status': task.status.key,
                    'due_date': task.dueDate?.toIso8601String(),
                  };
                  ok = await svc.updateTask(widget.existing!.id, updates);
                }
                if (!mounted) return;
                if (ok) {
                  Navigator.pop(context, true);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.success,
                    content: Text(isAr ? '✅ تَمّ الحِفظ' : '✅ Saved'),
                  ));
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    backgroundColor: AppColors.danger,
                    content: Text(svc.lastError ?? 'Failed'),
                  ));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
