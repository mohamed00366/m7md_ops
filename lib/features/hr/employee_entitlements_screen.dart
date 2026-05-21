// =============================================================================
// 💼 EmployeeEntitlementsScreen — مُستَحَقّات المُوَظَّف
// =============================================================================
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/entitlements_service.dart';
import '../../core/theme/app_colors.dart';
import '../../models/models.dart';
import '../../models/rbac.dart';

/// شاشة مُستَحَقّات المُوَظَّف
class EmployeeEntitlementsScreen extends StatefulWidget {
  final Employee employee;
  const EmployeeEntitlementsScreen({super.key, required this.employee});

  @override
  State<EmployeeEntitlementsScreen> createState() =>
      _EmployeeEntitlementsScreenState();
}

class _EmployeeEntitlementsScreenState
    extends State<EmployeeEntitlementsScreen> {
  bool _loading = true;
  bool _paying = false;
  EmployeeEntitlements? _data;
  List<LeaveSalaryPayment> _history = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await EntitlementsService.instance.calculateFor(widget.employee.id);
    final h = await EntitlementsService.instance.historyFor(widget.employee.id);
    if (mounted) {
      setState(() {
        _data = d;
        _history = h;
        _error = d == null ? EntitlementsService.instance.lastError : null;
        _loading = false;
      });
    }
  }

  Future<void> _payLeaveSalary() async {
    final auth = context.read<AuthProvider>();
    if (_data == null) return;

    final isAr = AppStrings.of(context).isAr;
    final includeTicket = _data!.eligibleForTicket && _data!.ticketAmount > 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAr ? 'تَأكيد صَرف راتِب الإجازة' : 'Confirm Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(isAr ? 'المُوَظَّف' : 'Employee', widget.employee.fullName),
            _row(isAr ? 'الراتِب الأَساسيّ' : 'Basic Salary',
                _money(_data!.basicSalary)),
            _row(isAr ? 'مَبلَغ راتِب الإجازة' : 'Leave Salary',
                _money(_data!.leaveSalaryAmount)),
            if (includeTicket)
              _row(isAr ? 'التَذكِرة' : 'Ticket',
                  _money(_data!.ticketAmount)),
            const Divider(),
            _row(
              isAr ? 'الإجماليّ' : 'Total',
              _money(_data!.leaveSalaryAmount +
                  (includeTicket ? _data!.ticketAmount : 0)),
              bold: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isAr ? 'إلغاء' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'صَرف' : 'Pay'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _paying = true);
    final result = await EntitlementsService.instance.recordLeaveSalaryPayment(
      employeeId: widget.employee.id,
      amount: _data!.leaveSalaryAmount,
      days: _data!.leaveDaysPerYear,
      ticketPaid: includeTicket,
      ticketAmount: includeTicket ? _data!.ticketAmount : 0,
      paidByAccountId: auth.account?.id,
    );
    if (!mounted) return;
    setState(() => _paying = false);

    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.success,
        content: Text(isAr ? '✅ تَمَّ الصَرف بِنَجاح' : '✅ Payment recorded'),
      ));
      _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.danger,
        content: Text('❌ ${EntitlementsService.instance.lastError}'),
      ));
    }
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w700)),
          ],
        ),
      );

  String _money(double v) => '${NumberFormat('#,##0.00').format(v)}';

  @override
  Widget build(BuildContext context) {
    final isAr = AppStrings.of(context).isAr;
    final auth = context.watch<AuthProvider>();
    final canPayLeave = auth.isSuperAdmin ||
        auth.permissions.contains(P.entitlementsPayLeaveSalary);

    // 🆕 يَعمَل كَـ Tab body — بِدون Scaffold/AppBar (المُحيط يُوَفِّر AppBar)
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.danger)),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text(isAr ? 'إعادة المُحاوَلة' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1️⃣ مَعلومات الخِدمة
          _serviceCard(isAr),
          const SizedBox(height: 12),
          // 2️⃣ راتِب الإجازة
          _leaveSalaryCard(isAr, canPayLeave),
          const SizedBox(height: 12),
          // 3️⃣ نِهاية الخِدمة
          _eosCard(isAr),
          const SizedBox(height: 12),
          // 4️⃣ التَذكِرة
          _ticketCard(isAr),
          const SizedBox(height: 16),
          // 5️⃣ السِجِلّ
          if (_history.isNotEmpty) _historyCard(isAr),
          const SizedBox(height: 16),
          if (_data?.referenceLaw != null) ...[
            Text(
              '📜 ${_data!.referenceLaw!}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ===========================================================================
  Widget _serviceCard(bool isAr) {
    final d = _data!;
    final years = d.yearsOfService.floor();
    final months = d.monthsOfService % 12;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.work_history, color: AppColors.brand),
              const SizedBox(width: 8),
              Text(isAr ? 'مَعلومات الخِدمة' : 'Service Info',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ]),
            const Divider(),
            _row(isAr ? 'تاريخ الانضِمام' : 'Joining Date',
                widget.employee.joiningDate != null
                    ? DateFormat('yyyy-MM-dd')
                        .format(widget.employee.joiningDate!)
                    : '—'),
            _row(
                isAr ? 'مُدَّة الخِدمة' : 'Length of Service',
                isAr
                    ? '$years سَنة و $months شَهر'
                    : '$years yrs $months mo'),
            _row(isAr ? 'الراتِب الأَساسيّ' : 'Basic Salary',
                _money(d.basicSalary), bold: true),
          ],
        ),
      ),
    );
  }

  Widget _leaveSalaryCard(bool isAr, bool canPay) {
    final d = _data!;
    final color = d.eligibleForLeave ? AppColors.success : AppColors.warning;
    return Card(
      color: color.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.beach_access, color: color),
              const SizedBox(width: 8),
              Text(isAr ? '🏖 راتِب الإجازة' : 'Leave Salary',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
              const Spacer(),
              if (d.eligibleForLeave)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isAr ? 'مُؤَهَّل' : 'Eligible',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900),
                  ),
                ),
            ]),
            const Divider(),
            if (d.eligibleForLeave) ...[
              _row(isAr ? 'الأَيّام' : 'Days',
                  '${d.leaveDaysPerYear} ${isAr ? 'يَوم' : 'days'}'),
              _row(isAr ? 'المَبلَغ المُستَحَقّ' : 'Amount Due',
                  _money(d.leaveSalaryAmount),
                  bold: true),
              const SizedBox(height: 8),
              if (canPay)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _paying ? null : _payLeaveSalary,
                    icon: _paying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.payments),
                    label: Text(_paying
                        ? (isAr ? 'جارٍ الصَرف...' : 'Processing...')
                        : (isAr ? 'صَرف راتِب الإجازة' : 'Pay Leave Salary')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ),
            ] else
              Text(
                isAr
                    ? 'المُوَظَّف يَحتاج إكمال 12 شَهر مِن تاريخ الانضِمام لِيَستَحِقّ راتِب الإجازة.'
                    : 'Employee needs 12 months of service to be eligible for leave salary.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _eosCard(bool isAr) {
    final d = _data!;
    final color = d.eligibleForEos ? AppColors.success : AppColors.warning;
    return Card(
      color: color.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.account_balance, color: color),
              const SizedBox(width: 8),
              Text(isAr ? '🏁 نِهاية الخِدمة' : 'End of Service',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
              const Spacer(),
              if (d.eligibleForEos)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isAr ? 'مُؤَهَّل' : 'Eligible',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900),
                  ),
                ),
            ]),
            const Divider(),
            if (d.eligibleForEos) ...[
              _row(isAr ? 'مَبلَغ المُكافأة' : 'Gratuity Amount',
                  _money(d.eosAmount),
                  bold: true),
              if (d.eosBreakdown.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  isAr ? 'التَفاصيل:' : 'Breakdown:',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 4),
                ...d.eosBreakdown.entries.map((e) => Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2),
                      child: Text(
                        '• ${e.key}: ${e.value}',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.grey),
                      ),
                    )),
              ],
            ] else
              Text(
                isAr
                    ? 'المُوَظَّف يَحتاج إكمال سَنة كامِلة مِن الخِدمة.'
                    : 'Employee needs at least 1 year of service.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _ticketCard(bool isAr) {
    final d = _data!;
    final color = d.eligibleForTicket ? AppColors.success : Colors.grey;
    return Card(
      color: color.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.flight, color: color),
              const SizedBox(width: 8),
              Text(isAr ? '✈ تَذكِرة السَفَر' : 'Travel Ticket',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  d.eligibleForTicket
                      ? (isAr ? 'مُؤَهَّل' : 'Eligible')
                      : (isAr ? 'غَير مُؤَهَّل' : 'Not Eligible'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ]),
            const Divider(),
            if (d.eligibleForTicket && d.ticketAmount > 0)
              _row(isAr ? 'مَبلَغ التَذكِرة' : 'Ticket Amount',
                  _money(d.ticketAmount),
                  bold: true)
            else
              Text(
                isAr
                    ? 'هذا المُوَظَّف لا يَستَحِقّ تَذكِرة سَفَر.\nيُمكِن تَفعيلها مِن بِطاقة المُوَظَّف.'
                    : 'This employee is not eligible for travel ticket.\nCan be enabled from employee card.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _historyCard(bool isAr) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.history, color: AppColors.brand),
              const SizedBox(width: 8),
              Text(isAr ? '📋 سِجِلّ المَدفوعات' : 'Payment History',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15)),
            ]),
            const Divider(),
            ..._history.take(10).map((p) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.payments,
                          size: 16, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          DateFormat('yyyy-MM-dd').format(p.paymentDate),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      Text(
                        _money(p.amount + p.ticketAmount),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
