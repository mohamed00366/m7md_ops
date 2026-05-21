// =============================================================================
// 📅✅ خِدمة الأَحداث المُخَصَّصة + قائِمة المَهامّ (To-Do)
// =============================================================================
import 'supabase_service.dart';

/// نَوع الحَدَث المُخَصَّص
enum CustomEventType {
  meeting,
  training,
  holiday,
  reminder,
  event,
  other;

  String get key {
    switch (this) {
      case meeting:
        return 'meeting';
      case training:
        return 'training';
      case holiday:
        return 'holiday';
      case reminder:
        return 'reminder';
      case event:
        return 'event';
      case other:
        return 'other';
    }
  }

  String labelAr() {
    switch (this) {
      case meeting:
        return '🤝 اجتِماع';
      case training:
        return '🎓 تَدريب';
      case holiday:
        return '🎉 عُطلة';
      case reminder:
        return '⏰ تَذكير';
      case event:
        return '📅 حَدَث';
      case other:
        return '📌 أُخرى';
    }
  }

  String labelEn() {
    switch (this) {
      case meeting:
        return '🤝 Meeting';
      case training:
        return '🎓 Training';
      case holiday:
        return '🎉 Holiday';
      case reminder:
        return '⏰ Reminder';
      case event:
        return '📅 Event';
      case other:
        return '📌 Other';
    }
  }

  static CustomEventType fromKey(String? k) {
    switch (k) {
      case 'meeting':
        return CustomEventType.meeting;
      case 'training':
        return CustomEventType.training;
      case 'holiday':
        return CustomEventType.holiday;
      case 'reminder':
        return CustomEventType.reminder;
      case 'event':
        return CustomEventType.event;
      default:
        return CustomEventType.other;
    }
  }
}

/// أَولَوِيّة المَهَمَّة
enum TaskPriority {
  low,
  normal,
  high,
  urgent;

  String get key {
    switch (this) {
      case low:
        return 'low';
      case normal:
        return 'normal';
      case high:
        return 'high';
      case urgent:
        return 'urgent';
    }
  }

  String labelAr() {
    switch (this) {
      case low:
        return '🟢 مُنخَفِضة';
      case normal:
        return '🔵 عادِيّة';
      case high:
        return '🟠 عالِية';
      case urgent:
        return '🔴 عاجِلة';
    }
  }

  static TaskPriority fromKey(String? k) {
    switch (k) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      case 'urgent':
        return TaskPriority.urgent;
      default:
        return TaskPriority.normal;
    }
  }
}

/// حالة المَهَمَّة
enum TaskStatus {
  todo,
  inProgress,
  done,
  cancelled;

  String get key {
    switch (this) {
      case todo:
        return 'todo';
      case inProgress:
        return 'in_progress';
      case done:
        return 'done';
      case cancelled:
        return 'cancelled';
    }
  }

  String labelAr() {
    switch (this) {
      case todo:
        return '📋 لِلتَنفيذ';
      case inProgress:
        return '🔄 قَيد التَنفيذ';
      case done:
        return '✅ مُنجَزة';
      case cancelled:
        return '❌ مُلغاة';
    }
  }

  static TaskStatus fromKey(String? k) {
    switch (k) {
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'done':
        return TaskStatus.done;
      case 'cancelled':
        return TaskStatus.cancelled;
      default:
        return TaskStatus.todo;
    }
  }
}

// ============================================================
// نَموذَج حَدَث مُخَصَّص
// ============================================================
class CustomEvent {
  final String id;
  final CustomEventType type;
  final String title;
  final String? description;
  final String? location;
  final DateTime startDate;
  final DateTime? endDate;
  final String? startTime; // HH:mm
  final String? endTime;
  final String recurrence; // none/daily/weekly/monthly/yearly
  final String? countryId;
  final String color; // hex
  final String? icon;
  final int notifyBeforeDays;
  final String? createdByAccountId;
  final DateTime? createdAt;

  CustomEvent({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    this.location,
    required this.startDate,
    this.endDate,
    this.startTime,
    this.endTime,
    this.recurrence = 'none',
    this.countryId,
    this.color = '#4338CA',
    this.icon,
    this.notifyBeforeDays = 0,
    this.createdByAccountId,
    this.createdAt,
  });

  factory CustomEvent.fromJson(Map<String, dynamic> j) => CustomEvent(
        id: j['id'] as String,
        type: CustomEventType.fromKey(j['type'] as String?),
        title: (j['title'] ?? '') as String,
        description: j['description'] as String?,
        location: j['location'] as String?,
        startDate: DateTime.parse(j['start_date'] as String),
        endDate: j['end_date'] == null
            ? null
            : DateTime.tryParse(j['end_date'] as String),
        startTime: j['start_time'] as String?,
        endTime: j['end_time'] as String?,
        recurrence: (j['recurrence'] ?? 'none') as String,
        countryId: j['country_id'] as String?,
        color: (j['color'] ?? '#4338CA') as String,
        icon: j['icon'] as String?,
        notifyBeforeDays: (j['notify_before_days'] ?? 0) as int,
        createdByAccountId: j['created_by_account_id'] as String?,
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'] as String),
      );

  Map<String, dynamic> toCreatePayload() => {
        'type': type.key,
        'title': title,
        if (description != null) 'description': description,
        if (location != null) 'location': location,
        'start_date':
            startDate.toIso8601String().substring(0, 10),
        if (endDate != null)
          'end_date': endDate!.toIso8601String().substring(0, 10),
        if (startTime != null) 'start_time': startTime,
        if (endTime != null) 'end_time': endTime,
        'recurrence': recurrence,
        if (countryId != null) 'country_id': countryId,
        'color': color,
        if (icon != null) 'icon': icon,
        'notify_before_days': notifyBeforeDays,
      };
}

// ============================================================
// نَموذَج مَهَمَّة (To-Do)
// ============================================================
class UserTask {
  final String id;
  final String accountId;
  final String title;
  final String? description;
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime? dueDate;
  final String? assignedByAccountId;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final DateTime? completedAt;
  final DateTime? createdAt;

  UserTask({
    required this.id,
    required this.accountId,
    required this.title,
    this.description,
    this.priority = TaskPriority.normal,
    this.status = TaskStatus.todo,
    this.dueDate,
    this.assignedByAccountId,
    this.relatedEntityType,
    this.relatedEntityId,
    this.completedAt,
    this.createdAt,
  });

  factory UserTask.fromJson(Map<String, dynamic> j) => UserTask(
        id: j['id'] as String,
        accountId: j['account_id'] as String,
        title: (j['title'] ?? '') as String,
        description: j['description'] as String?,
        priority: TaskPriority.fromKey(j['priority'] as String?),
        status: TaskStatus.fromKey(j['status'] as String?),
        dueDate: j['due_date'] == null
            ? null
            : DateTime.tryParse(j['due_date'] as String),
        assignedByAccountId: j['assigned_by_account_id'] as String?,
        relatedEntityType: j['related_entity_type'] as String?,
        relatedEntityId: j['related_entity_id'] as String?,
        completedAt: j['completed_at'] == null
            ? null
            : DateTime.tryParse(j['completed_at'] as String),
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse(j['created_at'] as String),
      );

  Map<String, dynamic> toCreatePayload() => {
        'account_id': accountId,
        'title': title,
        if (description != null) 'description': description,
        'priority': priority.key,
        'status': status.key,
        if (dueDate != null) 'due_date': dueDate!.toIso8601String(),
        if (assignedByAccountId != null)
          'assigned_by_account_id': assignedByAccountId,
        if (relatedEntityType != null)
          'related_entity_type': relatedEntityType,
        if (relatedEntityId != null)
          'related_entity_id': relatedEntityId,
      };

  bool get isOverdue {
    if (dueDate == null) return false;
    if (status == TaskStatus.done || status == TaskStatus.cancelled) {
      return false;
    }
    return dueDate!.isBefore(DateTime.now());
  }

  bool get isDueToday {
    if (dueDate == null) return false;
    if (status == TaskStatus.done || status == TaskStatus.cancelled) {
      return false;
    }
    final now = DateTime.now();
    return dueDate!.year == now.year &&
        dueDate!.month == now.month &&
        dueDate!.day == now.day;
  }
}

// ============================================================
// 🆕 الأَدوار وَالمُشارَكة
// ============================================================
enum ParticipantRole {
  responsible,
  participant,
  watcher;

  String get key {
    switch (this) {
      case responsible:
        return 'responsible';
      case participant:
        return 'participant';
      case watcher:
        return 'watcher';
    }
  }

  String labelAr() {
    switch (this) {
      case responsible:
        return '🎯 مَسؤول';
      case participant:
        return '👥 مُشارِك';
      case watcher:
        return '👁 مُتابِع';
    }
  }

  static ParticipantRole fromKey(String? k) {
    switch (k) {
      case 'responsible':
        return ParticipantRole.responsible;
      case 'watcher':
        return ParticipantRole.watcher;
      default:
        return ParticipantRole.participant;
    }
  }
}

enum RsvpStatus {
  pending,
  confirmed,
  declined,
  attended,
  noShow;

  String get key {
    switch (this) {
      case pending:
        return 'pending';
      case confirmed:
        return 'confirmed';
      case declined:
        return 'declined';
      case attended:
        return 'attended';
      case noShow:
        return 'no_show';
    }
  }

  String labelAr() {
    switch (this) {
      case pending:
        return '⏳ بِانتِظار الرَدّ';
      case confirmed:
        return '✅ مُؤَكَّد';
      case declined:
        return '❌ مُعتَذِر';
      case attended:
        return '🟢 حَضَر';
      case noShow:
        return '🔴 لَم يَحضُر';
    }
  }

  static RsvpStatus fromKey(String? k) {
    switch (k) {
      case 'confirmed':
        return RsvpStatus.confirmed;
      case 'declined':
        return RsvpStatus.declined;
      case 'attended':
        return RsvpStatus.attended;
      case 'no_show':
        return RsvpStatus.noShow;
      default:
        return RsvpStatus.pending;
    }
  }
}

class EventParticipant {
  final String id;
  final String eventId;
  final String? accountId;
  final String? employeeId;
  final ParticipantRole role;
  final RsvpStatus rsvpStatus;
  final String? rsvpNote;
  final DateTime? notifiedAt;

  // Joined data
  final String? displayName;
  final String? displayCode;

  EventParticipant({
    required this.id,
    required this.eventId,
    this.accountId,
    this.employeeId,
    required this.role,
    this.rsvpStatus = RsvpStatus.pending,
    this.rsvpNote,
    this.notifiedAt,
    this.displayName,
    this.displayCode,
  });

  factory EventParticipant.fromJson(Map<String, dynamic> j) {
    String? name;
    String? code;
    final acc = j['accounts'];
    if (acc is Map) {
      name = acc['full_name'] as String?;
      code = acc['username'] as String?;
    }
    final emp = j['employees'];
    if (emp is Map) {
      name ??= emp['full_name'] as String?;
      code ??= emp['code'] as String?;
    }
    return EventParticipant(
      id: j['id'] as String,
      eventId: j['event_id'] as String,
      accountId: j['account_id'] as String?,
      employeeId: j['employee_id'] as String?,
      role: ParticipantRole.fromKey(j['role'] as String?),
      rsvpStatus: RsvpStatus.fromKey(j['rsvp_status'] as String?),
      rsvpNote: j['rsvp_note'] as String?,
      notifiedAt: j['notified_at'] == null
          ? null
          : DateTime.tryParse(j['notified_at'] as String),
      displayName: name,
      displayCode: code,
    );
  }
}

class TaskAssignee {
  final String id;
  final String taskId;
  final String accountId;
  final ParticipantRole role;
  final DateTime? completedAt;
  final String? displayName;

  TaskAssignee({
    required this.id,
    required this.taskId,
    required this.accountId,
    required this.role,
    this.completedAt,
    this.displayName,
  });

  factory TaskAssignee.fromJson(Map<String, dynamic> j) {
    String? name;
    final acc = j['accounts'];
    if (acc is Map) name = acc['full_name'] as String?;
    return TaskAssignee(
      id: j['id'] as String,
      taskId: j['task_id'] as String,
      accountId: j['account_id'] as String,
      role: ParticipantRole.fromKey(j['role'] as String?),
      completedAt: j['completed_at'] == null
          ? null
          : DateTime.tryParse(j['completed_at'] as String),
      displayName: name,
    );
  }
}

// ============================================================
// الخِدمة الرَئيسيّة
// ============================================================
class EventsTasksService {
  EventsTasksService._();
  static final instance = EventsTasksService._();

  String? lastError;

  // ============================================================
  // 🆕 EVENT PARTICIPANTS
  // ============================================================

  Future<List<EventParticipant>> listEventParticipants(String eventId) async {
    final c = SupabaseService().client;
    try {
      final rows = await c
          .from('event_participants')
          .select('*, accounts(full_name, username), employees(full_name, code)')
          .eq('event_id', eventId)
          .order('role')
          .order('added_at');
      return (rows as List)
          .map((r) => EventParticipant.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  /// أَضِف مُشارِكين دَفعة واحِدة لِحَدَث
  Future<int> addEventParticipants({
    required String eventId,
    required List<({String? accountId, String? employeeId, ParticipantRole role})>
        participants,
    String? addedBy,
  }) async {
    if (participants.isEmpty) return 0;
    final c = SupabaseService().client;
    try {
      final payload = participants.map((p) {
        final m = <String, dynamic>{
          'event_id': eventId,
          'role': p.role.key,
          if (addedBy != null) 'added_by': addedBy,
        };
        if (p.accountId != null) m['account_id'] = p.accountId;
        if (p.employeeId != null) m['employee_id'] = p.employeeId;
        return m;
      }).toList();
      final res = await c.from('event_participants').insert(payload).select();
      return (res as List).length;
    } catch (e) {
      lastError = e.toString();
      return 0;
    }
  }

  Future<bool> removeParticipant(String participantId) async {
    final c = SupabaseService().client;
    try {
      await c.from('event_participants').delete().eq('id', participantId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<bool> updateRsvp({
    required String participantId,
    required RsvpStatus status,
    String? note,
  }) async {
    final c = SupabaseService().client;
    try {
      final updates = <String, dynamic>{
        'rsvp_status': status.key,
        'rsvp_at': DateTime.now().toIso8601String(),
      };
      if (note != null) updates['rsvp_note'] = note;
      await c.from('event_participants').update(updates).eq('id', participantId);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  /// قائِمة الأَحداث التي يُشارِك فيها مُوَظَّف/حِساب
  Future<List<Map<String, dynamic>>> listMyEvents({
    String? accountId,
    String? employeeId,
  }) async {
    final c = SupabaseService().client;
    try {
      var q = c
          .from('event_participants')
          .select('id, role, rsvp_status, rsvp_note, '
              'company_events(id, type, title, description, location, '
              'start_date, end_date, start_time, end_time, color)');
      if (accountId != null) {
        q = q.eq('account_id', accountId);
      } else if (employeeId != null) {
        q = q.eq('employee_id', employeeId);
      }
      final rows = await q;
      return (rows as List).cast<Map<String, dynamic>>();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  // ============================================================
  // 🆕 TASK ASSIGNEES
  // ============================================================

  Future<List<TaskAssignee>> listTaskAssignees(String taskId) async {
    final c = SupabaseService().client;
    try {
      final rows = await c
          .from('task_assignees')
          .select('*, accounts(full_name)')
          .eq('task_id', taskId)
          .order('role');
      return (rows as List)
          .map((r) => TaskAssignee.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<int> addTaskAssignees({
    required String taskId,
    required List<({String accountId, ParticipantRole role})> assignees,
  }) async {
    if (assignees.isEmpty) return 0;
    final c = SupabaseService().client;
    try {
      final payload = assignees
          .map((a) => {
                'task_id': taskId,
                'account_id': a.accountId,
                'role': a.role.key,
              })
          .toList();
      final res = await c.from('task_assignees').insert(payload).select();
      return (res as List).length;
    } catch (e) {
      lastError = e.toString();
      return 0;
    }
  }

  // ============================================================
  // 🆕 CONFLICT DETECTION
  // ============================================================

  /// يَفحَص هَل لَدَى المُوَظَّف تَعارُض في تاريخ مُحَدَّد
  /// يَرجِع رِسالة وَصف التَعارُض أَو null لَو لا تَعارُض
  Future<String?> checkConflict({
    required String employeeId,
    required DateTime date,
  }) async {
    final c = SupabaseService().client;
    try {
      final dateStr = date.toIso8601String().substring(0, 10);

      // 1) فَحص الإجازات
      final leaves = await c
          .from('employee_leave_requests')
          .select('leave_type, start_date, end_date')
          .eq('employee_id', employeeId)
          .eq('status', 'approved')
          .lte('start_date', dateStr)
          .gte('end_date', dateStr);
      if ((leaves as List).isNotEmpty) {
        final l = leaves.first as Map;
        return '⚠️ في إجازة (${l['leave_type']}) حَتّى ${l['end_date']}';
      }

      // 2) فَحص الأَحداث الأُخرى
      final events = await c
          .from('event_participants')
          .select('company_events(title, start_date)')
          .eq('employee_id', employeeId);
      for (final r in (events as List)) {
        final e = (r as Map)['company_events'];
        if (e is Map && e['start_date'] == dateStr) {
          return '⚠️ لَه حَدَث آخَر نَفس اليَوم: ${e['title']}';
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // ============================================================
  // EVENTS
  // ============================================================

  /// قائِمة أَحداث في فَترة + فَلتَر دَولة (اختِياريّ)
  Future<List<CustomEvent>> listEvents({
    required DateTime from,
    required DateTime to,
    String? countryId,
  }) async {
    final c = SupabaseService().client;
    try {
      var q = c
          .from('company_events')
          .select()
          .gte('start_date', from.toIso8601String().substring(0, 10))
          .lte('start_date', to.toIso8601String().substring(0, 10));
      if (countryId != null) q = q.eq('country_id', countryId);
      final rows = await q.order('start_date');
      return (rows as List)
          .map((r) => CustomEvent.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<CustomEvent?> createEvent(CustomEvent e) async {
    final c = SupabaseService().client;
    try {
      final r = await c
          .from('company_events')
          .insert(e.toCreatePayload())
          .select()
          .single();
      return CustomEvent.fromJson(Map<String, dynamic>.from(r));
    } catch (ex) {
      lastError = ex.toString();
      return null;
    }
  }

  Future<bool> updateEvent(String id, Map<String, dynamic> updates) async {
    final c = SupabaseService().client;
    try {
      await c.from('company_events').update(updates).eq('id', id);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<bool> deleteEvent(String id) async {
    final c = SupabaseService().client;
    try {
      await c.from('company_events').delete().eq('id', id);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  // ============================================================
  // TASKS
  // ============================================================

  /// كُلّ مَهامّ حِساب مُحَدَّد (أَو طاقَم كامِل لَو viewTeam=true)
  Future<List<UserTask>> listMyTasks({
    required String accountId,
    bool includeDone = false,
  }) async {
    final c = SupabaseService().client;
    try {
      var q = c.from('tasks').select().eq('account_id', accountId);
      if (!includeDone) {
        q = q.neq('status', 'done').neq('status', 'cancelled');
      }
      final rows = await q.order('due_date', ascending: true, nullsFirst: false);
      return (rows as List)
          .map((r) => UserTask.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (e) {
      lastError = e.toString();
      return [];
    }
  }

  Future<UserTask?> createTask(UserTask t) async {
    final c = SupabaseService().client;
    try {
      final r =
          await c.from('tasks').insert(t.toCreatePayload()).select().single();
      return UserTask.fromJson(Map<String, dynamic>.from(r));
    } catch (e) {
      lastError = e.toString();
      return null;
    }
  }

  Future<bool> updateTaskStatus(String id, TaskStatus newStatus) async {
    final c = SupabaseService().client;
    try {
      await c.from('tasks').update({'status': newStatus.key}).eq('id', id);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<bool> updateTask(String id, Map<String, dynamic> updates) async {
    final c = SupabaseService().client;
    try {
      await c.from('tasks').update(updates).eq('id', id);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }

  Future<bool> deleteTask(String id) async {
    final c = SupabaseService().client;
    try {
      await c.from('tasks').delete().eq('id', id);
      return true;
    } catch (e) {
      lastError = e.toString();
      return false;
    }
  }
}
