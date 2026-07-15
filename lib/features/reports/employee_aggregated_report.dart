// =============================================================================
// 👤 Employee Aggregated Report — Full 360° in ONE screen
// =============================================================================
// Pick one employee → see EVERYTHING across all sections at once:
//   • Identity card (basic info)
//   • Attendance summary (last 30 days)
//   • Leaves (all + current vacation)
//   • Discipline (deductions / warnings)
//   • Documents (with expiry urgency)
//   • Insurance
//   • Uniform issuances
//   • Forms submitted
//   • Recent audit activity
// =============================================================================
import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/services/m7_log.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';
import '../../models/models.dart';
import '../../repositories/mock_repository.dart';
import '../../shared/m7_app_bar.dart';

class EmployeeAggregatedReport extends StatefulWidget {
  final String? employeeId; // null = show picker
  const EmployeeAggregatedReport({super.key, this.employeeId});

  @override
  State<EmployeeAggregatedReport> createState() =>
      _EmployeeAggregatedReportState();
}

class _EmployeeAggregatedReportState extends State<EmployeeAggregatedReport> {
  String? _selectedId;
  Employee? _employee;
  bool _loading = false;

  // Section data
  int _clockIns30d = 0;
  int _clockOuts30d = 0;
  DateTime? _lastClockIn;
  List<Map<String, dynamic>> _leaves = [];
  List<Map<String, dynamic>> _deductions = [];
  List<Map<String, dynamic>> _documents = [];
  List<Map<String, dynamic>> _insurance = [];
  List<Map<String, dynamic>> _uniforms = [];
  List<Map<String, dynamic>> _forms = [];
  List<Map<String, dynamic>> _audit = [];
  // 🆕 الأَحداث وَالمَهامّ
  List<Map<String, dynamic>> _myEvents = [];
  List<Map<String, dynamic>> _myTasks = [];

  @override
  void initState() {
    super.initState();
    _selectedId = widget.employeeId;
    if (_selectedId != null) _loadAll();
  }

  Future<void> _loadAll() async {
    if (_selectedId == null) return;
    setState(() => _loading = true);
    final supa = SupabaseService();
    final repo = MockRepository();
    final empMatches =
        repo.employees.where((e) => e.id == _selectedId).toList();
    _employee = empMatches.isEmpty ? null : empMatches.first;
    if (!supa.isReady) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final empId = _selectedId!;
      final now = DateTime.now();
      final since30 = now.subtract(const Duration(days: 30));

      // 1) Attendance (last 30 days)
      final clk = await supa.client
          .from('point_terminal_clock_logs')
          .select('action, created_at')
          .eq('employee_id', empId)
          .gte('created_at', since30.toIso8601String())
          .order('created_at', ascending: false)
          .limit(500);
      _clockIns30d = (clk as List)
          .where((r) => (r as Map)['action'] == 'clock_in')
          .length;
      _clockOuts30d = clk
          .where((r) => (r as Map)['action'] == 'clock_out')
          .length;
      _lastClockIn = clk
          .where((r) => (r as Map)['action'] == 'clock_in')
          .map((r) => DateTime.tryParse(((r as Map)['created_at'] as String?) ?? ''))
          .where((d) => d != null)
          .cast<DateTime>()
          .firstOrNull;

      // 2) Leaves
      final lvs = await supa.client
          .from('employee_leave_requests')
          .select(
              'id, leave_type, start_date, end_date, days_count, status, late_status, return_date')
          .eq('employee_id', empId)
          .order('start_date', ascending: false)
          .limit(200);
      _leaves = (lvs as List).cast<Map<String, dynamic>>();

      // 3) Deductions
      final ded = await supa.client
          .from('employee_deductions')
          .select(
              'id, warning_number, category, reason, amount, currency, status, applied_at, signed_at')
          .eq('employee_id', empId)
          .order('applied_at', ascending: false)
          .limit(200);
      _deductions = (ded as List).cast<Map<String, dynamic>>();

      // 4) Documents
      try {
        final docs = await supa.client
            .from('employee_documents')
            .select(
                'id, doc_type, doc_type_label, expiry_date, file_url, uploaded_at')
            .eq('employee_id', empId)
            .order('expiry_date', ascending: true)
            .limit(200);
        _documents = (docs as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _documents = [];
      }

      // 5) Insurance
      try {
        final ins = await supa.client
            .from('employee_insurance')
            .select(
                'id, insurance_company, policy_number, policy_type, coverage_tier, start_date, end_date, status, premium_amount, dependents_count')
            .eq('employee_id', empId)
            .order('end_date', ascending: false)
            .limit(50);
        _insurance = (ins as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _insurance = [];
      }

      // 6) Uniforms
      try {
        final uni = await supa.client
            .from('employee_uniforms')
            .select('id, item_name, quantity, issue_no, issued_at')
            .eq('employee_id', empId)
            .order('issued_at', ascending: false)
            .limit(100);
        _uniforms = (uni as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _uniforms = [];
      }

      // 7) Forms
      try {
        final frm = await supa.client
            .from('form_submissions')
            .select(
                'id, form_no, status, current_step, total_steps, created_at, submitted_at, form_templates(name_ar, name_en, category)')
            .eq('employee_id', empId)
            .order('created_at', ascending: false)
            .limit(100);
        _forms = (frm as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _forms = [];
      }

      // 8) Audit (events touching this employee)
      try {
        final aud = await supa.client
            .from('audit_log')
            .select('id, entity_type, action, created_at, by_user_name')
            .eq('entity_id', empId)
            .order('created_at', ascending: false)
            .limit(50);
        _audit = (aud as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _audit = [];
      }

      // 9) 🆕 الأَحداث التي يُشارِك فيها (event_participants)
      try {
        // ابحَث عَن account_id المَربوط بِالمُوَظَّف
        final accLink = await supa.client
            .from('accounts')
            .select('id')
            .eq('employee_id', empId)
            .maybeSingle();
        final linkedAccountId = accLink == null ? null : accLink['id'];

        // اِجمَع الأَحداث عَبر employee_id أَو account_id
        final evRows = await supa.client
            .from('event_participants')
            .select(
                'id, role, rsvp_status, rsvp_note, '
                'company_events(id, type, title, description, location, '
                'start_date, end_date, start_time, end_time, color)')
            .or(linkedAccountId == null
                ? 'employee_id.eq.$empId'
                : 'employee_id.eq.$empId,account_id.eq.$linkedAccountId');
        _myEvents = (evRows as List).cast<Map<String, dynamic>>();

        // المَهامّ
        if (linkedAccountId != null) {
          final tRows = await supa.client
              .from('tasks')
              .select(
                  'id, title, description, priority, status, due_date, '
                  'related_entity_type, related_entity_id, completed_at')
              .eq('account_id', linkedAccountId)
              .order('due_date',
                  ascending: true, nullsFirst: false)
              .limit(100);
          _myTasks = (tRows as List).cast<Map<String, dynamic>>();
        } else {
          _myTasks = [];
        }
      } catch (e) {
        M7Log.error('EmpAggReport', 'events_tasks', error: e);
        _myEvents = [];
        _myTasks = [];
      }
    } catch (e) {
      M7Log.error('EmpAggReport', 'loadAll', error: e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    return Scaffold(
      appBar: M7AppBar(
        title: isAr ? '👤 المُلَفّ الشامِل للمُوَظَّف' : '👤 Employee 360°',
        actions: [
          if (_selectedId != null)
            M7AppBarAction(
              icon: Icons.refresh,
              tooltip: isAr ? 'تَحديث' : 'Refresh',
              onPressed: _loadAll,
            ),
          M7AppBarAction(
            icon: Icons.swap_horiz,
            tooltip: isAr ? 'تَغيير المُوَظَّف' : 'Change employee',
            onPressed: _pickEmployee,
          ),
        ],
      ),
      body: _selectedId == null
          ? _emptyPicker(isAr)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _identityCard(isAr),
                      const SizedBox(height: 10),
                      _kpiGrid(isAr),
                      const SizedBox(height: 10),
                      _section(isAr ? '🏖 الإجازات' : '🏖 Leaves',
                          _leaves.length, _leavesList(isAr)),
                      _section(
                          isAr ? '💰 الخَصومات / الإنذارات' : '💰 Deductions',
                          _deductions.length,
                          _deductionsList(isAr)),
                      _section(isAr ? '📁 الوَثائِق' : '📁 Documents',
                          _documents.length, _documentsList(isAr)),
                      _section(isAr ? '🏥 التَأمين' : '🏥 Insurance',
                          _insurance.length, _insuranceList(isAr)),
                      _section(isAr ? '👕 اليونيفورم' : '👕 Uniforms',
                          _uniforms.length, _uniformsList(isAr)),
                      _section(isAr ? '📝 النَماذِج' : '📝 Forms',
                          _forms.length, _formsList(isAr)),
                      _section(
                          isAr ? '🎉 أَحداثي' : '🎉 My Events',
                          _myEvents.length,
                          _eventsList(isAr)),
                      _section(
                          isAr ? '✅ مَهامّي' : '✅ My Tasks',
                          _myTasks.length,
                          _tasksList(isAr)),
                      _section(isAr ? '🕒 السِجِلّ' : '🕒 Audit',
                          _audit.length, _auditList(isAr)),
                    ],
                  ),
                ),
    );
  }

  Widget _emptyPicker(bool isAr) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.person_search,
                size: 80, color: AppColors.brand),
            const SizedBox(height: 16),
            Text(
              isAr ? 'اِختَر مُوَظَّفاً لعَرض مُلَفّه الشامِل' : 'Pick an employee',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _pickEmployee,
              icon: const Icon(Icons.search),
              label: Text(isAr ? 'اِختِيار مُوَظَّف' : 'Choose employee'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickEmployee() async {
    final repo = MockRepository();
    final isAr = AppStrings.of(context).isAr;
    final search = TextEditingController();
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(builder: (ctx, setSt) {
          final all = repo.employees
              .where((e) =>
                  query.isEmpty ||
                  e.fullName.toLowerCase().contains(query.toLowerCase()) ||
                  e.code.toLowerCase().contains(query.toLowerCase()))
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.8,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    color: Colors.grey.shade400,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: search,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: isAr ? 'بَحث…' : 'Search…',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onChanged: (v) => setSt(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: all.length,
                      itemBuilder: (_, i) {
                        final e = all[i];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                            child: Text(
                              e.fullName.isNotEmpty ? e.fullName[0] : '?',
                              style: const TextStyle(
                                  color: AppColors.brand,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                          title: Text(e.fullName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13)),
                          subtitle: Text(
                              '${e.code} · ${e.jobTitle} · ${e.department}',
                              style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.pop(ctx, e.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    if (picked != null) {
      setState(() => _selectedId = picked);
      _loadAll();
    }
  }

  Widget _identityCard(bool isAr) {
    final e = _employee;
    if (e == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(isAr ? 'بَيانات المُوَظَّف غَير مَوجودة' : 'Employee not found'),
        ),
      );
    }
    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.brand.withValues(alpha: 0.15),
                  child: Text(
                    e.fullName.isNotEmpty ? e.fullName[0] : '?',
                    style: const TextStyle(
                        color: AppColors.brand,
                        fontWeight: FontWeight.w900,
                        fontSize: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.fullName,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text(
                          '${e.code}${e.fileNo.isNotEmpty ? " · ${e.fileNo}" : ""} · ${e.jobTitle}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700)),
                      const SizedBox(height: 2),
                      Text('${e.department} · ${e.nationality}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                _statusBadge(e.status, isAr),
              ],
            ),
            const Divider(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _miniInfo(Icons.phone, e.mobile.isEmpty ? '—' : e.mobile),
                _miniInfo(Icons.email, e.email.isEmpty ? '—' : e.email),
                _miniInfo(
                    Icons.cake,
                    e.birthDate == null
                        ? '—'
                        : e.birthDate!.toIso8601String().substring(0, 10)),
                _miniInfo(
                    Icons.work,
                    e.joiningDate == null
                        ? '—'
                        : e.joiningDate!.toIso8601String().substring(0, 10)),
                _miniInfo(Icons.attach_money,
                    'AED ${e.totalSalary.toStringAsFixed(0)}'),
                if (e.basicSalary > 0)
                  _miniInfo(Icons.account_balance_wallet_outlined,
                      '${isAr ? "أساسي" : "Basic"} ${e.basicSalary.toStringAsFixed(0)}'),
                if (e.housingAllowance > 0)
                  _miniInfo(Icons.home_outlined,
                      '${isAr ? "سكن" : "Housing"} ${e.housingAllowance.toStringAsFixed(0)}'),
                if (e.transportAllowance > 0)
                  _miniInfo(Icons.directions_bus_outlined,
                      '${isAr ? "مواصلات" : "Transport"} ${e.transportAllowance.toStringAsFixed(0)}'),
                if (e.otherAllowances > 0)
                  _miniInfo(Icons.add_circle_outline,
                      '${isAr ? "أخرى" : "Other"} ${e.otherAllowances.toStringAsFixed(0)}'),
                if (e.overtimeHourlyRate > 0)
                  _miniInfo(Icons.timer_outlined,
                      '${isAr ? "ساعة أوفرتايم" : "OT/hr"} ${e.overtimeHourlyRate.toStringAsFixed(0)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(EntityStatus st, bool isAr) {
    Color c;
    String label;
    switch (st) {
      case EntityStatus.active:
        c = AppColors.success;
        label = isAr ? 'نَشِط' : 'Active';
        break;
      case EntityStatus.vacation:
        c = AppColors.warning;
        label = isAr ? 'في إجازة' : 'Vacation';
        break;
      case EntityStatus.inactive:
        c = AppColors.danger;
        label = isAr ? 'مُعَطَّل' : 'Inactive';
        break;
      case EntityStatus.maintenance:
        c = Colors.orange;
        label = isAr ? 'صيانة' : 'Maint.';
        break;
      case EntityStatus.suspended:
        c = Colors.deepOrange;
        label = isAr ? 'مَوقوف' : 'Suspended';
        break;
      case EntityStatus.resigned:
        c = Colors.redAccent;
        label = isAr ? 'مُستَقيل' : 'Resigned';
        break;
      case EntityStatus.terminated:
        c = Colors.red.shade900;
        label = isAr ? 'مَفصول' : 'Terminated';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: c)),
    );
  }

  Widget _miniInfo(IconData i, String t) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: 13, color: Colors.grey.shade700),
      const SizedBox(width: 4),
      Text(t,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade800)),
    ]);
  }

  Widget _kpiGrid(bool isAr) {
    final approvedLeaves =
        _leaves.where((l) => l['status'] == 'approved').length;
    final pendingLeaves =
        _leaves.where((l) => l['status'] == 'pending').length;
    final activeDed = _deductions.where((d) => d['status'] == 'active').length;
    final dedTotal = _deductions
        .where((d) => d['status'] == 'active')
        .fold<double>(0,
            (sum, d) => sum + ((d['amount'] as num?) ?? 0).toDouble());
    final expiringDocs = _documents.where((d) {
      final s = d['expiry_date'] as String?;
      if (s == null) return false;
      final dt = DateTime.tryParse(s);
      if (dt == null) return false;
      final daysLeft = dt.difference(DateTime.now()).inDays;
      return daysLeft <= 60;
    }).length;
    final activeInsurance = _insurance.where((i) {
      final e = i['end_date'] as String?;
      if (e == null) return false;
      final dt = DateTime.tryParse(e);
      if (dt == null) return false;
      return dt.isAfter(DateTime.now());
    }).length;

    final kpis = <_Kpi>[
      _Kpi(isAr ? 'دُخول 30ي' : 'In 30d', '$_clockIns30d',
          Icons.login, AppColors.success),
      _Kpi(isAr ? 'خُروج 30ي' : 'Out 30d', '$_clockOuts30d',
          Icons.logout, Colors.indigo),
      _Kpi(isAr ? 'إجازات' : 'Leaves',
          '$approvedLeaves / $pendingLeaves', Icons.beach_access,
          AppColors.warning),
      _Kpi(isAr ? 'إنذارات' : 'Warnings', '$activeDed',
          Icons.warning, AppColors.danger),
      _Kpi(isAr ? 'إجمالي خَصم' : 'Deducted',
          'AED ${dedTotal.toStringAsFixed(0)}', Icons.money_off,
          Colors.deepOrange),
      _Kpi(isAr ? 'وَثائق قريبة' : 'Docs ≤60d', '$expiringDocs',
          Icons.event_busy, Colors.purple),
      _Kpi(isAr ? 'تَأمين نَشِط' : 'Insurance', '$activeInsurance',
          Icons.health_and_safety, Colors.teal),
      _Kpi(isAr ? 'نَماذِج' : 'Forms', '${_forms.length}',
          Icons.assignment, AppColors.brand),
      // 🆕 KPIs الأَحداث وَالمَهامّ
      _Kpi(isAr ? 'أَحداث' : 'Events', '${_myEvents.length}',
          Icons.event_available, Colors.indigo),
      _Kpi(
          isAr ? 'مَهامّ' : 'Tasks',
          '${_myTasks.where((t) => t['status'] != 'done' && t['status'] != 'cancelled').length}',
          Icons.task_alt,
          Colors.purple),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: kpis.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (_, i) {
        final k = kpis[i];
        return Container(
          decoration: BoxDecoration(
            color: k.color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: k.color.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(k.icon, color: k.color, size: 18),
              const SizedBox(height: 2),
              Text(k.value,
                  style: TextStyle(
                      color: k.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w900),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 1),
              Text(k.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 9,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String title, int count, Widget body) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Row(
          children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$count',
                  style: const TextStyle(
                      color: AppColors.brand,
                      fontWeight: FontWeight.w900,
                      fontSize: 11)),
            ),
          ],
        ),
        children: [
          if (count == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('—',
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            )
          else
            body,
        ],
      ),
    );
  }

  Widget _leavesList(bool isAr) {
    return Column(
      children: _leaves.take(20).map((l) {
        final st = (l['status'] as String?) ?? '';
        Color c = Colors.grey;
        if (st == 'approved') c = AppColors.success;
        if (st == 'pending') c = AppColors.warning;
        if (st == 'rejected') c = AppColors.danger;
        final late = (l['late_status'] as String?) ?? '';
        final isLate = late == 'late_pending' || late == 'returned_late';
        return ListTile(
          dense: true,
          leading: Icon(Icons.beach_access, color: c, size: 18),
          title: Text(
              '${l['leave_type']} · ${l['days_count']} ${isAr ? 'يَوم' : 'd'}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          subtitle: Text(
              '${l['start_date']} → ${l['end_date']}'
              '${isLate ? "  ⚠️" : ""}',
              style: const TextStyle(fontSize: 11)),
          trailing: Text(st,
              style: TextStyle(
                  fontSize: 10, color: c, fontWeight: FontWeight.w800)),
        );
      }).toList(),
    );
  }

  Widget _deductionsList(bool isAr) {
    return Column(
      children: _deductions.take(20).map((d) {
        final amt = (d['amount'] as num?)?.toDouble() ?? 0;
        final st = (d['status'] as String?) ?? '';
        final signed = d['signed_at'] != null;
        return ListTile(
          dense: true,
          leading: const Icon(Icons.warning,
              color: AppColors.danger, size: 18),
          title: Text(
              '${d['warning_number']} · AED ${amt.toStringAsFixed(0)}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          subtitle: Text('${d['category']} · ${d['reason']}',
              style: const TextStyle(fontSize: 11)),
          trailing: Icon(
              signed ? Icons.check_circle : Icons.pending,
              color: signed ? AppColors.success : AppColors.warning,
              size: 16),
        );
      }).toList(),
    );
  }

  Widget _documentsList(bool isAr) {
    return Column(
      children: _documents.take(20).map((d) {
        final exp = d['expiry_date'] as String?;
        DateTime? expDt;
        if (exp != null) expDt = DateTime.tryParse(exp);
        Color c = Colors.grey;
        String urgency = '';
        if (expDt != null) {
          final days = expDt.difference(DateTime.now()).inDays;
          if (days < 0) {
            c = AppColors.danger;
            urgency = isAr ? '🔴 مُنتَهية' : '🔴 Expired';
          } else if (days <= 30) {
            c = AppColors.danger;
            urgency = isAr ? '⚠️ $days يَوم' : '⚠️ $days d';
          } else if (days <= 90) {
            c = AppColors.warning;
            urgency = isAr ? '⏰ $days يَوم' : '⏰ $days d';
          } else {
            c = AppColors.success;
            urgency = isAr ? '✅ $days يَوم' : '✅ $days d';
          }
        }
        return ListTile(
          dense: true,
          leading: Icon(Icons.description, color: c, size: 18),
          title: Text(
              (d['doc_type_label'] as String?) ??
                  (d['doc_type'] as String?) ??
                  '?',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          subtitle: Text('${isAr ? "يَنتَهي" : "Expires"} $exp',
              style: const TextStyle(fontSize: 11)),
          trailing: Text(urgency,
              style: TextStyle(
                  color: c, fontSize: 10, fontWeight: FontWeight.w800)),
        );
      }).toList(),
    );
  }

  Widget _insuranceList(bool isAr) {
    return Column(
      children: _insurance.take(10).map((i) {
        final end = i['end_date'] as String?;
        return ListTile(
          dense: true,
          leading: const Icon(Icons.health_and_safety,
              color: Colors.teal, size: 18),
          title: Text(
              '${i['insurance_company']} · ${i['policy_type']}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          subtitle: Text(
              '#${i['policy_number']} · ${isAr ? "حتى" : "until"} $end',
              style: const TextStyle(fontSize: 11)),
          trailing: Text('${i['coverage_tier'] ?? "—"}',
              style: const TextStyle(fontSize: 10)),
        );
      }).toList(),
    );
  }

  Widget _uniformsList(bool isAr) {
    return Column(
      children: _uniforms.take(20).map((u) {
        return ListTile(
          dense: true,
          leading: const Icon(Icons.checkroom,
              color: AppColors.brand, size: 18),
          title: Text('${u['item_name']} × ${u['quantity']}',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          subtitle: Text(
              '${u['issue_no']} · ${(u['issued_at'] as String?)?.substring(0, 10) ?? ""}',
              style: const TextStyle(fontSize: 11)),
        );
      }).toList(),
    );
  }

  Widget _formsList(bool isAr) {
    return Column(
      children: _forms.take(20).map((f) {
        final tpl = f['form_templates'];
        final name = tpl is Map
            ? (isAr
                ? (tpl['name_ar'] as String?) ?? '?'
                : (tpl['name_en'] as String?) ?? '?')
            : '?';
        final st = (f['status'] as String?) ?? '';
        Color c = Colors.grey;
        if (st == 'approved') c = AppColors.success;
        if (st == 'pending') c = AppColors.warning;
        if (st == 'rejected') c = AppColors.danger;
        return ListTile(
          dense: true,
          leading: Icon(Icons.assignment, color: c, size: 18),
          title: Text('${f['form_no']} · $name',
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          subtitle: Text(
              '${f['current_step']}/${f['total_steps']} · ${(f['created_at'] as String?)?.substring(0, 10) ?? ""}',
              style: const TextStyle(fontSize: 11)),
          trailing: Text(st,
              style: TextStyle(
                  color: c, fontSize: 10, fontWeight: FontWeight.w800)),
        );
      }).toList(),
    );
  }

  Widget _auditList(bool isAr) {
    return Column(
      children: _audit.take(15).map((a) {
        return ListTile(
          dense: true,
          leading: const Icon(Icons.history, color: Colors.grey, size: 18),
          title: Text('${a['action']} · ${a['entity_type']}',
              style: const TextStyle(fontSize: 11)),
          subtitle: Text(
              '${a['by_user_name'] ?? "?"} · ${(a['created_at'] as String?)?.substring(0, 16) ?? ""}',
              style: const TextStyle(fontSize: 10)),
        );
      }).toList(),
    );
  }

  // 🆕 قائِمة الأَحداث التي يُشارِك فيها المُوَظَّف
  Widget _eventsList(bool isAr) {
    return Column(
      children: _myEvents.take(20).map((p) {
        final e = p['company_events'];
        if (e is! Map) return const SizedBox.shrink();
        final title = (e['title'] as String?) ?? '?';
        final start = (e['start_date'] as String?) ?? '';
        final startT = (e['start_time'] as String?) ?? '';
        final location = (e['location'] as String?) ?? '';
        final role = (p['role'] as String?) ?? 'participant';
        final rsvp = (p['rsvp_status'] as String?) ?? 'pending';

        Color roleColor;
        String roleLabel;
        IconData roleIcon;
        switch (role) {
          case 'responsible':
            roleColor = AppColors.danger;
            roleLabel = isAr ? 'مَسؤول' : 'Responsible';
            roleIcon = Icons.shield_outlined;
            break;
          case 'watcher':
            roleColor = Colors.blueGrey;
            roleLabel = isAr ? 'مُتابِع' : 'Watcher';
            roleIcon = Icons.visibility_outlined;
            break;
          default:
            roleColor = AppColors.brand;
            roleLabel = isAr ? 'مُشارِك' : 'Participant';
            roleIcon = Icons.groups_outlined;
        }

        Color rsvpColor;
        String rsvpLabel;
        switch (rsvp) {
          case 'confirmed':
          case 'attended':
            rsvpColor = AppColors.success;
            rsvpLabel = isAr ? '✅ مُؤَكَّد' : '✅ Confirmed';
            break;
          case 'declined':
          case 'no_show':
            rsvpColor = AppColors.danger;
            rsvpLabel = isAr ? '❌ مُعتَذِر' : '❌ Declined';
            break;
          default:
            rsvpColor = AppColors.warning;
            rsvpLabel = isAr ? '⏳ بِانتِظار' : '⏳ Pending';
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: ListTile(
            dense: true,
            leading: Icon(roleIcon, color: roleColor, size: 22),
            title: Text(title,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '$start${startT.isEmpty ? "" : " · $startT"}'
                    '${location.isEmpty ? "" : " · $location"}',
                    style: const TextStyle(fontSize: 10)),
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(roleLabel,
                        style: TextStyle(
                            color: roleColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: rsvpColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(rsvpLabel,
                        style: TextStyle(
                            color: rsvpColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800)),
                  ),
                ]),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // 🆕 قائِمة مَهامّ المُوَظَّف
  Widget _tasksList(bool isAr) {
    return Column(
      children: _myTasks.take(20).map((t) {
        final title = (t['title'] as String?) ?? '?';
        final priority = (t['priority'] as String?) ?? 'normal';
        final status = (t['status'] as String?) ?? 'todo';
        final due = t['due_date'] as String?;
        final relatedType = (t['related_entity_type'] as String?) ?? '';

        Color prioColor;
        switch (priority) {
          case 'urgent':
            prioColor = AppColors.danger;
            break;
          case 'high':
            prioColor = AppColors.warning;
            break;
          case 'low':
            prioColor = AppColors.success;
            break;
          default:
            prioColor = AppColors.brand;
        }

        Color statusColor;
        String statusLabel;
        switch (status) {
          case 'done':
            statusColor = AppColors.success;
            statusLabel = isAr ? '✅ مُنجَزة' : '✅ Done';
            break;
          case 'in_progress':
            statusColor = AppColors.warning;
            statusLabel = isAr ? '🔄 جارية' : '🔄 In progress';
            break;
          case 'cancelled':
            statusColor = Colors.grey;
            statusLabel = isAr ? '❌ مُلغاة' : '❌ Cancelled';
            break;
          default:
            statusColor = Colors.grey.shade700;
            statusLabel = isAr ? '📋 لِلتَنفيذ' : '📋 To-do';
        }

        // هَل مُتَأَخِّرة؟
        bool isOverdue = false;
        if (due != null && status != 'done' && status != 'cancelled') {
          final dueDt = DateTime.tryParse(due);
          if (dueDt != null && dueDt.isBefore(DateTime.now())) {
            isOverdue = true;
          }
        }

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 2),
          color: isOverdue
              ? AppColors.danger.withValues(alpha: 0.05)
              : status == 'done'
                  ? AppColors.success.withValues(alpha: 0.05)
                  : null,
          child: ListTile(
            dense: true,
            leading: Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: prioColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                decoration: status == 'done'
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            subtitle: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 4),
              if (due != null)
                Text(
                  '${isAr ? "📅" : "📅"} ${due.substring(0, 10)}'
                  '${isOverdue ? (isAr ? " ⚠️ مُتَأَخِّرة" : " ⚠️ Overdue") : ""}',
                  style: TextStyle(
                      fontSize: 9,
                      color: isOverdue
                          ? AppColors.danger
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.w700),
                ),
              if (relatedType.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                    relatedType == 'event'
                        ? (isAr ? '🎉 حَدَث' : '🎉 Event')
                        : '🔗 $relatedType',
                    style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade700,
                        fontStyle: FontStyle.italic)),
              ],
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _Kpi {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  _Kpi(this.label, this.value, this.icon, this.color);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
